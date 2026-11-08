# gen2 → gen3 migration roadmap (checklist across sessions)

## Context
Gen3 (k3s on hogwarts, Flux Operator, `clusters/prod-gen3`) is up with only `podinfo` deployed. Gen2 (kubeadm on chimaera) runs everything else. Instead of lifting everything at once, migrate in small, independently verifiable steps across several Claude Code sessions. Downtime is acceptable. Hard problems: **Longhorn data** (don't clobber gen2 backups), **DNS cutover** (two external-dns instances must not fight), **ingress** (HAProxy `.28` gen2 vs `.29` gen3, eero port-forward).

## What this session delivers (on approval)
1. **Roadmap doc** `home-kubernetes/docs/plans/2026-11-08-gen2-to-gen3-migration.md` — the checkbox plan below (verbatim, tickable per session; each phase = one session).
2. **gen3 CRDs** (Phase 1, small and safe):
   - New `crds/prod-gen3/kustomization.yaml` — copy of `crds/prod-gen2/kustomization.yaml` (resources: `../base/{istio,gateway-api,cert-manager,flux-operator,sealed-secrets,onepassword,kube-prometheus-stack,external-dns,longhorn}`).
   - New `clusters/prod-gen3/00-crds-ks.yaml` (copy of `clusters/prod-gen2/00-crds-ks.yaml`, path `./crds/prod-gen3/`), added to `clusters/prod-gen3/kustomization.yaml`. Leave `02-apps-ks.yaml` as-is for now (no `dependsOn` infra yet; add `dependsOn: crds-ks` only when infra-ks exists).
   - Learnings to capture in doc: flux-operator CRDs already installed by operator on gen3 (check for ownership conflict with `crds/base/flux-operator` before applying — may need to drop it from the gen3 overlay); `istio-base` is a HelmRelease so it needs helm-controller (present); `kube-prometheus-stack` CRDs via chart.
3. Verify: `kustomize build crds/prod-gen3`, `pre-commit`, then after merge `scripts/get-kubeconfig.sh prod-gen3` → `flux get ks -A` and `kubectl get crd | grep -E 'istio|gateway|cert-manager|sealed|onepassword|monitoring|longhorn|externaldns'`.

Commit per-repo inside `home-kubernetes` only (never the outer repo).

## Key design decisions (defaults; flag if you disagree)
- **Shared state is external** (NAS Postgres/Redis/NFS) — an app must only ever run in ONE cluster at a time (Harbor, media, coder, home-hud). Migrating = scale to 0 in gen2 → enable in gen3.
- **Per-app DNS cutover, not big-bang.** Pi-hole A records are per-HTTPRoute. Step 0 of DNS: change gen2 pihole external-dns to `policy: upsert-only` (currently `sync` + `registry: noop`, which deletes anything it doesn't see — two instances would delete each other's records). Gen3 instance also starts `upsert-only`. An app flips by removing it from `applications/prod-gen2` and adding to `applications/prod-gen3`; gen3 external-dns writes the record → `.29`. Flip both back to `sync` only after gen2 is retired. Your "hard-stop external-dns on old" is the fallback if upsert-only misbehaves.
- **Gen3 Gateway annotations target `.29`** (gen3 HAProxy LXC, VMID 213) via patch in `infra/prod-gen3/istio`, vs `.28` in gen2. Before DNS exists, test with `curl --resolve host:443:192.168.6.29`.
- **Public (Cloudflare) cutover is a single step at the end of Wave 2**: eero 80/443 forward `.28` → `.29`, Cloudflare external-dns on gen3 takes over. Public apps (blog, fui-components, diagram-maker?, umami, podinfo, apex) must all be live on gen3 first.
- **Let's Encrypt rate limit**: both clusters issuing `wildcard-local-tls` / public certs for identical names — max 5 duplicate certs/week. Use LE staging ClusterIssuer on gen3 for testing, switch to prod issuer at cutover.
- **No image-update-automation on gen3** until gen2 is retired (it pushes to `main`; two writers conflict).
- **Longhorn on gen3 never sees an empty-volume backup write into gen2's target** (see Phase 3).
- Gen3 specifics already known (from `home-playbooks/docs/plans/2026-11-07-gen3-flux-handover.md`): istio-cni paths `/var/lib/rancher/k3s/agent/etc/cni/net.d` + `/var/lib/rancher/k3s/data/current/bin`; k3s control plane runs in one process (adjust prometheus scrape); metrics-server from Flux; Longhorn data path `/mnt/ssd` (already on workers; keep `nodeSelector amd64`); service DNS `10.43.0.10` (grep found no hardcoded `10.96.0.10` in this repo); re-seal `op-credentials` (`scripts/op-connect-secret.sh`); workers are 2×16GB on hogwarts + 1×6GB on chimaera (watch ARC/Harbor/Prometheus memory).

---

## Roadmap checklist (copy into the doc)

### Phase 0 — Prep / doc hygiene (session 0)
- [x] (2026-11-08: 6/6 nodes Ready, Flux all Ready at 2440ab23, podinfo healthy) Confirm `kubectl --context prod-gen3` works (`scripts/get-kubeconfig.sh prod-gen3`); `flux get all -A` healthy; podinfo reconciled.
- [x] (done in working trees; `dns-expert`, outer CLAUDE.md, HOSTS.md, playbooks README, gen3 README, handover doc, secrets-longhorn-nas) Fix stale docs: `.claude/agents/dns-expert.md` (says gen3 has no HK manifests; `.28` vs `.29`), `home-playbooks/docs/HOSTS.md` NAS = Asustor vs Synology, gen3 README "flux handover not started" vs actually run 2026-11-07, `secrets-longhorn-nas.md` (CIFS vs `nfs://`).
- [x] (2026-11-08: LXC live, config has .42/.43 backends, HTTP backend DOWN as expected, HTTPS tcp-mode has no health check so shows UP regardless) Verify HAProxy gen3 (`.29`) backends exist (workers `.42/.43`, NodePorts 30080/30443, send-proxy-v2) — gen3 README still lists as TODO.
- [x] (Appendix A) Inventory sheet in the doc: per workload → namespace, storage (Longhorn/NFS/none), external deps (Postgres/Redis DB index), public vs LAN, secrets.
- [x] Longhorn backup-store safety copy: 2026-11-08 copied via NAS web UI to `/volume1/Backups/longhorn-prod.pre-gen3-copy` and `longhorn-nonprod.pre-gen3-copy` (user-reported; file counts not independently verified, SSH to NAS blocked/reset). Phase 3 gate item 1 satisfied.

### Phase 1 — CRDs (session 1) ← this session
- [x] `crds/prod-gen3/kustomization.yaml` + `clusters/prod-gen3/00-crds-ks.yaml`; wire into cluster kustomization.
- [x] flux-operator CRDs already exist on gen3 (installed by operator, 4 `fluxcd.controlplane.io` CRDs). Same situation as gen2 (Ansible-installed operator), where `crds-ks` adopts them; kept in overlay. If `crds-ks` reports an apply conflict, drop `../base/flux-operator` from the gen3 overlay.
- [x] `kustomize build` passes for `crds/prod-gen3` and `clusters/prod-gen3`; [x] (2026-11-08: home-kubernetes has NO `.pre-commit-config.yaml`; `pre-commit run` errors with InvalidConfigError, so nothing to run. Verified with `kubectl kustomize` instead) pre-commit; [x] merge; [x] (2026-11-08: crds-ks Ready at main@8d9226c1, 66 CRDs) `crds-ks` Ready on gen3; CRDs present.
- [x] Record learnings in doc (above).

### Phase 2 — Foundation infra (session 2) — DONE 2026-11-08 — `infra/prod-gen3/` + `clusters/prod-gen3/01-infra-ks.yaml` (dependsOn crds-ks); apps-ks gets `dependsOn: infra-ks`
- [x] (merge A fb21950a + merge B 3b0e23a, 2026-11-08; infra-ks and apps-ks Ready) Create `infra/prod-gen3/kustomization.yaml` + `01-infra-ks.yaml` (dependsOn crds-ks), apps-ks dependsOn infra-ks. Merge A = priorityclass, sealed-secrets, metrics-server. Merge B = onepassword + cert-manager (needs the sealed `op-credentials`, which needs the gen3 controller from merge A first, hence two merges).
- [x] (2026-11-08: controller Running; key saved by user in 1Password as a Secure Note, `sealed-secrets-key-prod-gen3`) sealed-secrets: new controller key on gen3 → back up key to 1Password; re-seal anything gen3 needs.
- [x] (2026-11-08: op-connect + operator Running; test OnePasswordItem produced a Secret) onepassword (Connect + operator): re-seal `op-credentials` for gen3; verify a `OnePasswordItem` syncs.
- [x] (2026-11-08: only `letsencrypt-staging` exists; test cert `gen3-phase2-test.abbottland.io` issued via Cloudflare DNS-01, then deleted) cert-manager with **staging** issuer first; DNS-01 via Cloudflare token (OnePasswordItem); issue a test cert.
- [x] (2026-11-08: `kubectl top nodes` shows all 6) metrics-server from Flux (k3s one disabled) → `kubectl top nodes` works.

### Phase 3 — Storage (session 3 = nas-storage, session 4 = Longhorn)
- [x] (2026-11-08, session 3: main@71bd3da; HR nas-storage Ready, SC `nas-storage`; RWX test PVC Bound, write on worker-1 read on worker-2 OK; export `/volume1/ClusterStorage` allows 192.168.0.0/16 rw no_root_squash) **nas-storage** (NFS provisioner → `192.168.4.124:/volume1/ClusterStorage/prod-gen3`): deploy; test PVC bound; confirm gen3 nodes (192.168.6.x) allowed by NAS NFS export rules.
- [ ] **Longhorn safety gate (before any gen3 Longhorn install):**
  - [x] (done in Phase 0) Copy `/volume1/Backups/longhorn-prod` (and nonprod) to a second NAS location (`cp -a`/rsync or Asustor snapshot). Verify size/file count.
  - [x] (2026-11-08: 10 of 12 BackupVolumes backed up 2026-11-08 03:00; the 2 stale ones, `coder-workspaces` home volume and `arc-runners/arc-pnpm-store`, confirmed NOT needed by user, start empty on gen3) Confirm every gen2 volume has a recent successful backup. Still take a fresh manual backup of each volume right before its cutover. (Longhorn UI → Backup); take a fresh manual backup of each important volume right before cutover.
- [ ] Deploy Longhorn on gen3 with: `defaultDataPath: /mnt/ssd`, **no recurring jobs, no volumes, and backup target pointed at the existing `longhorn-prod` path read-only in practice** (nothing runs that would write). Alternative if comfortable: leave `backupTarget` empty initially and set it later just before restore. Verify prerequisites on workers (open-iscsi, `/mnt/ssd` ext4 present on .42/.43/.46) — Longhorn node check.
- [ ] Verify gen3 Longhorn lists gen2 backups (BackupVolumes) without modifying them.
- [ ] Restore rehearsal with ONE low-value volume (e.g. `turbo-cache` or `prowlarr-config`): Longhorn UI "Restore" from backup → new volume → PVC/PV (storageClass `longhorn`) → mount in a test pod → inspect data.
- [ ] **Before any gen3 backup is written**, switch gen3 `backupTarget` to a NEW path `nfs://192.168.4.124:/volume1/Backups/longhorn-prod-gen3` (create dir on NAS) so gen3 never writes into gen2's store. Re-do the `cifs-secret` OnePasswordItem on gen3.
- [ ] Port gen2 prod Longhorn overlay (`daily-backups` RecurringJob group `default`, 03:00, retain 7; Prometheus PVC opts out via label). Gen2 sets no `defaultReplicaCount` (chart default 3) — gen3 has exactly 3 workers, so 3 replicas = every volume on every worker; decide on 2.
- [ ] Set recurring backup job + replica count to suit 3 workers (2 on hogwarts NVMe, 1 on chimaera); document that 2 of 3 replicas share host hogwarts.
- [ ] Per-app data move procedure (documented in doc): scale app to 0 on gen2 → final Longhorn backup → restore on gen3 → create PVC bound to restored volume → enable app in gen3 overlay → verify → delete from gen2.
- [ ] Decision note: apps whose Longhorn data is disposable (turbo-cache, arc caches, Prometheus) → start empty instead of restoring.

### Phase 4 — Ingress + observability (sessions 5–6)
- [ ] **istio** (`infra/prod-gen3/istio` copying gen2 patches; ambient profile 1.30.*, chain istiod → istio-cni → ztunnel → istio-ingress DaemonSet NodePort 30080/30443, `externalTrafficPolicy: Local`, PROXY protocol): istio-cni with **k3s paths**; both Gateways (`istio-ingress`, `istio-ingress-public` incl. apex listener); `internal-apps-ip-allowlist` AuthorizationPolicy (check it admits `.29`/HAProxy source and gen3 pod CIDR — gen2 allowlist has 10.244/16; gen3 Calico pod CIDR is also 10.244.0.0/16 (service CIDR 10.43/16), so it should carry over - verify); Gateway annotation `cert-manager.io/cluster-issuer: letsencrypt-staging` and external-dns target → `192.168.6.29` via overlay patch.
- [ ] Smoke test via `curl --resolve` through `.29` to podinfo (HTTPRoute + TLS).
- [ ] **kube-prometheus-stack**: Longhorn PVC (fresh start; no restore), k3s control-plane scrape adjustments (disable kubeEtcd/scheduler/controller-manager ServiceMonitors or point at k3s metrics), Grafana dashboards (gitops-tagged per docs/claude-sessions), alerts routing. Grafana on gen3 reachable only via `--resolve` until DNS flip.
- [ ] Decide Prometheus remote scraping of gen2 during overlap (optional): keep gen2 Prometheus until retirement.

### Phase 5 — DNS prep (session 7) — no user-visible change
- [ ] gen2 PR: Pi-hole external-dns `policy: sync` → `upsert-only` (both pihole + verify cloudflare instance policy); confirm gen2 records unaffected.
- [ ] Deploy **pihole external-dns on gen3** with `upsert-only`, `registry: noop`, label `pihole-dns-enabled`, Pi-hole creds from 1Password. Initially no labelled routes on gen3 other than a test host (e.g. `podinfo-gen3.local.abbottland.io`).
- [ ] Deploy **Cloudflare external-dns on gen3** but with `--dry-run`/no `external-dns-enabled` routes (or zero replicas) until public cutover.
- [ ] Confirm Pi-hole (bananapi) itself stays out of k8s cutover: the in-cluster `pihole` app in `infra/base/pihole` (EndpointSlice proxy to bananapi) — move with ingress, no data.
- [ ] Verify `podinfo-gen3` resolves to `.29` from LAN and Tailscale; gen2 records unchanged.

### Phase 6 — Wave 1 apps: stateless / LAN-only (sessions 8–9)
Move each = remove from `applications/prod-gen2/kustomization.yaml`, add to `applications/prod-gen3/kustomization.yaml`, reconcile, verify, check DNS flipped.
- [ ] dashy (local chart via GitRepository; review per-cluster URL list), proxmox (+ Istio DestinationRule), asustor (Service/EndpointSlice → NAS; prod also has `nas-dnsendpoint.yaml` DNSEndpoint → needs external-dns `crd` source on gen3), haproxy (stats proxy → update EndpointSlice to `.29`'s stats when .28 retires), mcp-grafana, plex (EndpointSlice proxy only, no route)
- [ ] pihole proxy route (`infra/base/pihole` HTTPRoute → bananapi `.144:8081`) → gen3
- [ ] flux-operator web UI HTTPRoute + `flux-gitops` (flux-operator-mcp) → gen3 (`03-flux-gitops-ks`; hostnames `flux.local`, `flux-mcp.local` collide with gen2, so move them in this wave)
- [ ] Note: `home-assistant` is a proxy to `192.168.4.24` but public (`homeassistant.abbottland.io`, Cloudflare) → belongs to the public cutover (Phase 8), not here.

### Phase 7 — Wave 2 apps: stateful (sessions 10–13, one logical group per session)
- [ ] **media** stack (sonarr, radarr, prowlarr, qbittorrent, gluetun): config PVCs Longhorn restore; media NFS PV (`manual`, RWX); NAS Postgres shared — gen2 scaled to 0 first. Verify VPN (gluetun) works from gen3 node network.
- [ ] **home-hud** (backup/media NFS PVs, NAS Postgres), **coder** (NAS Postgres), **openclaw** (Longhorn PVC restore).
- [ ] **harbor** + **harbor-cleanup** (registry on NFS PVC `nas-storage`, DB/Redis on NAS indexes 3,4,5,6,11,12 — only one cluster at a time; in-cluster Longhorn piece per helmrelease l.61/63). Check CI/ARC and other clusters pull from Harbor during outage; regcred secret.
- [ ] **arc** runners + cache server (needs Harbor, 1Password GH PAT; Longhorn/NFS caches start empty); check memory limits on 16GB workers.
- [ ] **plex** (hardware transcode? check GPU/devices; media NFS) — likely stays last/maybe needs `nodeSelector`.
- [ ] **public apps** (staged on gen3, not yet DNS-live): blog (apex `https-public-apex` listener), fui-components, diagram-maker, umami (+NAS Postgres; analytics host also LAN), home-assistant proxy, podinfo public host — all need regcred from Harbor and image-automation on gen2 only until Phase 9.

### Phase 8 — Public cutover (session 14)
- [ ] Gen3 cert issuer → production; wildcard + apex certs issued on gen3 (public HTTPS listeners incl. `https-public-apex`).
- [ ] Stop Cloudflare external-dns on gen2; start on gen3 (`external-dns-enabled` routes) — CNAMEs point to `abbottland.io` already, so mainly ownership changes; `cloudflare-ddns` stays wherever it lives (move it too).
- [ ] eero: change 80/443 port-forward from `192.168.6.28` → `192.168.6.29`. Test externally (phone off WiFi). Keep rollback = flip eero back.
- [ ] HAProxy `.29` source ACL contains LAN + Cloudflare ranges — verify refresh.
- [ ] Confirm Tailscale/remote access paths (bananapi subnet router) still reach gen3 LAN names; check whether eero hands out Pi-hole DNS.

### Phase 9 — Retire gen2 (session 15)
- [ ] Flip both external-dns on gen3 back to `sync`; remove gen2 external-dns.
- [ ] Enable image-update-automation on gen3 (`clusters/prod-gen3/image-update-automation.yaml`), remove from gen2.
- [ ] Final Longhorn backups of anything left; scale gen2 apps to 0; keep gen2 VMs powered off 2–4 weeks as rollback.
- [ ] Retire `.28` HAProxy LXC and Terraform (`home-playbooks/terraform/chimaera`), update `docs/HOSTS.md`, `NETWORK.md`, dns-expert agent.
- [ ] Optional: non-prod-gen2 handling (powered off), off-host etcd snapshot to NAS, dumbledore joining as controller (etcd quorum off hogwarts), Longhorn replicas rebalance.
- [ ] Delete `*-gen2` overlays / update CLAUDE.md and READMEs.

### Phase 2 learnings (2026-11-08)
- Two merges were needed: `op-credentials` can only be sealed once the gen3 sealed-secrets controller runs (merge A). For future rebuilds, restore the backed-up controller key *before* Flux installs the controller and no re-seal is needed.
- The Connect token in the dev shell (`OP_CONNECT_*`) is read-only: `op item create/list` fail in Connect mode and the REST API returns 403 on create. Writing to 1Password needs a real `op signin` or the UI.
- `1password-credentials-prod.json` / `.env` are not on disk, and no "Prod Gen2 Credentials File" item exists in the vault. `gen3` `op-credentials` was instead re-sealed straight from the live gen2 secret (`kubectl --context prod-gen2 ... | kubeseal --context prod-gen3 --scope namespace-wide --namespace op-connect`), so gen2 and gen3 share one Connect server identity (own Connect server per cluster is the alternative).
- `kubectl kustomize` forbids resource *files* outside the overlay dir; reference the base *directory* and use `$patch: delete` to drop pieces (op-connect HTTPRoute, `cloudflare-ddns`, `letsencrypt-prod`).
- home-kubernetes has no `.pre-commit-config.yaml`; gen2 context is added with `scripts/get-kubeconfig.sh prod-gen2`.


### Phase 3 learnings — nas-storage (2026-11-08)
- Gen3 uses its own NFS subdir `/volume1/ClusterStorage/prod-gen3` (gen2 uses `.../prod-gen2`); the dir had to be created on the NAS before merge (provisioner mount fails otherwise). `ror` alias (`ssh pabbott@192.168.4.124`) works without a password and allows read-only NAS checks.
- NAS export rules: `/etc/exports` grants `/volume1/ClusterStorage` to `192.168.0.0/16` (rw, no_root_squash, insecure), so gen3 nodes need no NAS change. NFS mounts come from node IPs, not pod IPs.
- Probe method: throwaway pods with an `nfs:` volume (`readOnly: true`) pinned via `nodeName` to each worker proved reachability before merge.
- `archiveOnDelete: 'true'`: deleting the test PVC left `/volume1/ClusterStorage/prod-gen3/archived-nas-storage-test-t` on the NAS. User deleted it by hand (verified).
- Longhorn gate: prod copy `longhorn-prod.pre-gen3-copy` 47,999 files/66.9 GB vs live 46,853/65.0 GB (copy larger, consistent with live pruning); nonprod copy identical (17,833 files). Two gen2 volumes have stale backups (see gate bullet).

- Longhorn only gets a disk on nodes labeled `node.longhorn.io/create-default-disk=true` (manual; controllers are untainted and have no `/mnt/ssd`). Documented in `docs/ai-reference-gen3-manual-steps.md`.

### Phase 3b plan — Longhorn (next session, not executed)
1. ~~User: create `/volume1/Backups/longhorn-prod-gen3` on the NAS~~ done 2026-11-08 (verified empty over SSH).
2. `infra/prod-gen3/longhorn`: base dir `../../base/longhorn`, `$patch: delete` the base HTTPRoute (no istio yet), `backupTarget: nfs://192.168.4.124:/volume1/Backups/longhorn-prod-gen3` from day one (gen2's value lives only in its overlay, so never inherit it), `defaultReplicaCount: 2`, `defaultDataPath: /mnt/ssd`, amd64 nodeSelector, NO RecurringJob yet.
3. Check whether `cifs-secret` is needed with `nfs://`; if so user creates/copies the 1Password item (dev-shell token is read-only).
4. Verify prerequisites on workers .42/.43/.46 (open-iscsi, `/mnt/ssd`) before merging; after merge check Longhorn nodes Ready and a test volume backup lands only in `longhorn-prod-gen3`.
5. Restore rehearsal from a SEPARATE temporary backup target on `longhorn-prod.pre-gen3-copy` (the copy, never live `longhorn-prod`); restore `prowlarr-config`, mount in a test pod, remove the target.
6. Then add `daily-backups` RecurringJob (03:00, retain 7), then the per-app data move procedure.

---

## Cross-cutting rollback / safety notes (to include in doc)
- Every phase is a separate commit/PR in `home-kubernetes`; `flux suspend ks <name>` stops a phase.
- Never run two instances of the same stateful app (shared NAS Postgres/Redis index/NFS).
- Redis DB-index allocation in `home-playbooks/playbooks/redis/README.md` — gen3 reuses same indexes (no new ones).
- Per-app rollback = revert the overlay move + re-enable gen2 (DNS flips back via external-dns upsert).
- Playbook/infra changes (HAProxy backends, etcd snapshot to NAS, eero) live in `home-playbooks`/manual — separate repo, separate commits.

## Critical files
- `home-kubernetes/crds/prod-gen2/kustomization.yaml` (copy to `crds/prod-gen3/`)
- `home-kubernetes/clusters/prod-gen2/00-crds-ks.yaml`, `01-infra-ks.yaml`, `02-apps-ks.yaml` (templates for gen3)
- `home-kubernetes/clusters/prod-gen3/{kustomization.yaml,02-apps-ks.yaml}`
- `home-kubernetes/infra/prod-gen2/**` (overlays to port), `infra/base/{longhorn,istio,external-dns,pihole,nas-storage}`
- `home-kubernetes/applications/prod-gen{2,3}/kustomization.yaml`
- `home-playbooks/terraform/hogwarts/haproxy.cfg`, `docs/plans/2026-11-07-gen3-flux-handover.md`

## Verification (this session)
- `kustomize build crds/prod-gen3` renders; `pre-commit run -a` in `home-kubernetes`.
- After merge: `kubectl --context prod-gen3 -n flux-system get kustomization crds-ks` Ready; CRDs listed; no impact on podinfo (`apps-ks` still Ready).
- Doc renders; every phase has unticked checkboxes.

---

## Appendix A — Workload inventory (prod-gen2, verified 2026-11-08 from manifests)

Storage: LH = Longhorn PVC, NFS = NAS PV/`nas-storage`, ext = NAS Postgres/Redis, none. Exposure: pub = Cloudflare, lan = Pi-hole only.

| Workload | Storage | Exposure | Notes / Phase |
|---|---|---|---|
| podinfo | none | lan+pub | already on gen3 (no routes yet) |
| dashy, proxmox, haproxy, mcp-grafana | none | lan | P6 |
| asustor | none | lan (+`nas.local` DNSEndpoint) | P6; needs external-dns `crd` source |
| plex | none (proxy to NAS) | none | P6 |
| pihole proxy, flux UI, flux-mcp | none | lan | P6 |
| home-assistant | none (proxy to 192.168.4.24) | pub | P7/P8 |
| blog, fui-components, diagram-maker | none | pub | P7/P8; NetworkPolicy + image automation (gen2 only until P9) |
| umami | ext Postgres | pub+lan | P7/P8 |
| coder | ext Postgres | lan | P7 |
| openclaw | LH 10Gi | lan | P7; restore or start fresh |
| media (sonarr/radarr/prowlarr/qbit/gluetun/byparr/mcp-*) | LH 1-5Gi x5, NFS 10Ti, ext Postgres | lan | P7; PIA/VPN |
| home-hud (+homelab-api, video-*, backup-worker) | NFS 10Ti x2, ext Postgres | lan | P7 |
| harbor, harbor-cleanup | NFS 50Gi, LH (trivy/jobservice), ext PG+Redis (idx 3,4,5,6,11,12) | lan | P7; one cluster at a time |
| arc (controller, runners, cache servers) | LH 20Gi + 30Gi, NFS 20Gi | lan | P7; start caches empty |
| Infra: kube-prometheus-stack | LH 20Gi (no backup) | lan | P4; start fresh |
| Infra: longhorn / nas-storage | NAS NFS backup target / `ClusterStorage` | lan | P3 |
| Infra: cloudflare-ddns | none | pub | P8 (prod only) |

Secrets: 1Password Connect (`OnePasswordItem`, vault Homelab) everywhere; only `op-credentials` is a SealedSecret (per-cluster key, re-seal for gen3).
