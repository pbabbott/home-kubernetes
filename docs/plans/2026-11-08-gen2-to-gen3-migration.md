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
- [x] Longhorn backup-store safety copy: 2026-11-08 copied via NAS web UI to `/volume1/Backups/longhorn-prod.pre-gen3-copy` and `longhorn-nonprod.pre-gen3-copy` (user-reported; file counts verified 2026-11-08 over SSH (`ror`): nonprod identical, prod copy 47,999 vs live 46,853 files). Phase 3 gate item 1 satisfied.

### Phase 1 — CRDs (session 1) — DONE
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
- [x] (both sub-items satisfied 2026-11-08, before the install) **Longhorn safety gate (before any gen3 Longhorn install):**
  - [x] (done in Phase 0) Copy `/volume1/Backups/longhorn-prod` (and nonprod) to a second NAS location (`cp -a`/rsync or Asustor snapshot). Verify size/file count.
  - [x] (2026-11-08: 10 of 12 BackupVolumes backed up 2026-11-08 03:00; the 2 stale ones, `coder-workspaces` home volume and `arc-runners/arc-pnpm-store`, confirmed NOT needed by user, start empty on gen3) Confirm every gen2 volume has a recent successful backup. Still take a fresh manual backup of each volume right before its cutover. (Longhorn UI → Backup); take a fresh manual backup of each important volume right before cutover.
- [x] (2026-11-08, main@84d12a2: HR longhorn Ready; 3 workers have /mnt/ssd disks, controllers none (needs manual node label, see ai-reference-gen3-manual-steps.md); backupTarget set to NEW longhorn-prod-gen3 from day one, no recurring jobs; prerequisites verified: open-iscsi/iscsid, /mnt/ssd ext4 98G) Deploy Longhorn on gen3 with: `defaultDataPath: /mnt/ssd`, **no recurring jobs, no volumes, and backup target pointed at the existing `longhorn-prod` path read-only in practice** (nothing runs that would write). Alternative if comfortable: leave `backupTarget` empty initially and set it later just before restore. Verify prerequisites on workers (open-iscsi, `/mnt/ssd` ext4 present on .42/.43/.46) — Longhorn node check.
- [x] (SKIPPED BY DESIGN: gen3 target is longhorn-prod-gen3, so gen2 backups are not listed; rehearsal reads the safety copy via a temporary target instead) Verify gen3 Longhorn lists gen2 backups (BackupVolumes) without modifying them.
- [x] (2026-11-08: restored `media/prowlarr-config` (2Gi) from `longhorn-prod.pre-gen3-copy` via temporary BackupTarget `rehearsal-copy`; Volume CR `fromBackup` restore finished in <20s; static PV/PVC bound; read-only pod saw 692 files/90MB incl. config.xml; test objects deleted; live store 46,853 and copy 47,999 files unchanged) Restore rehearsal with ONE low-value volume (e.g. `turbo-cache` or `prowlarr-config`): Longhorn UI "Restore" from backup → new volume → PVC/PV (storageClass `longhorn`) → mount in a test pod → inspect data.
- [x] (2026-11-08: done up front, gen3 never pointed at longhorn-prod; test volume+backup+delete wrote only to longhorn-prod-gen3, live longhorn-prod still 46,853 files; cifs-secret OnePasswordItem comes from base (same Homelab item)) **Before any gen3 backup is written**, switch gen3 `backupTarget` to a NEW path `nfs://192.168.4.124:/volume1/Backups/longhorn-prod-gen3` (create dir on NAS) so gen3 never writes into gen2's store. Re-do the `cifs-secret` OnePasswordItem on gen3.
- [x] (2026-11-08, main@aedcad8: RecurringJob `daily-backups` on gen3, group `default`, cron `0 2 * * *` UTC = 02:00 (gen2 is 03:00), retain 7, concurrency 1; replicas 2. The gen2 Prometheus opt-out label is not needed until Prometheus is restored on gen3 (Phase 4, fresh start)) Port gen2 prod Longhorn overlay (`daily-backups` RecurringJob group `default`, 03:00, retain 7; Prometheus PVC opts out via label). Gen2 sets no `defaultReplicaCount` (chart default 3) — gen3 has exactly 3 workers, so 3 replicas = every volume on every worker; decide on 2.
- [x] (2026-11-08: replica count 2 set in default setting + StorageClass; recurring job added at 02:00) Set recurring backup job + replica count to suit 3 workers (2 on hogwarts NVMe, 1 on chimaera); document that 2 of 3 replicas share host hogwarts.
- [x] (2026-11-08, branch phase3-data-move: runbook + rollback per step in `docs/ai-reference-gen3-data-move.md`, helper `scripts/longhorn-restore.sh` (dry-run default, refuses live store without `--allow-live-store`), volume table in Appendix B; dry-run of `media/prowlarr-config` from the safety copy into scratch ns passed (692 files, PVC bound, Flux SSA over it OK), scratch cleaned. Live-store restore also exercised 2026-11-08 17:11-17:16 UTC: approved gen2 Snapshot+Backup `data-move-final-prowlarr` Completed, temp BackupTarget `live-restore` (idle, left in place), restored via `--allow-live-store` into scratch ns (692 files), live store unchanged by target sync and restore) Per-app data move procedure: scale app to 0 on gen2 → final Longhorn backup → restore on gen3 → create PVC bound to restored volume → enable app in gen3 overlay → verify → delete from gen2.
- [x] (Appendix B) Decision note: start EMPTY for arc-runners caches (turbo-cache-storage, actions-cache-server-data, arc-pnpm-store), Prometheus, coder workspace home. RESTORE: openclaw, media configs, harbor trivy + jobservice.

### Phase 4 — Ingress + observability (sessions 5–6)
- [x] (2026-11-08, main@66e0b2f: istiod, istio-cni, ztunnel, istio-ingress DaemonSet 6/6 on NodePort 30080/30443 ETP Local; both Gateways Programmed incl. `https-public-apex`; staging certs wildcard-local-tls, wildcard-public-tls, apex-public-tls Ready. Deviations: istio-cni uses chart DEFAULT paths, not k3s paths (gen3 is Calico, see Phase 4 learnings); ztunnel needs `IPV6_ENABLED=false`) **istio** (`infra/prod-gen3/istio` copying gen2 patches; ambient profile 1.30.*, chain istiod → istio-cni → ztunnel → istio-ingress DaemonSet NodePort 30080/30443, `externalTrafficPolicy: Local`, PROXY protocol): istio-cni with **k3s paths**; both Gateways (`istio-ingress`, `istio-ingress-public` incl. apex listener); `internal-apps-ip-allowlist` AuthorizationPolicy (check it admits `.29`/HAProxy source and gen3 pod CIDR — gen2 allowlist has 10.244/16; gen3 Calico pod CIDR is also 10.244.0.0/16 (service CIDR 10.43/16), so it should carry over - verify); Gateway annotation `cert-manager.io/cluster-issuer: letsencrypt-staging` and external-dns target → `192.168.6.29` via overlay patch.
- [x] (2026-11-08, main@aa237d0: `podinfo-gen3.local.abbottland.io` and `podinfo-gen3.abbottland.io` return 200 via .29 with the staging cert, http -> 301 https, unknown host 404; HAProxy .29 `gen3-cluster-http` k3sw1/k3sw2 UP; no DNS labels or external-dns on gen3) Smoke test via `curl --resolve` through `.29` to podinfo (HTTPRoute + TLS).
- [x] (2026-11-08, main@5857966: overlay `infra/prod-gen3/kube-prometheus-stack`; Prometheus/Grafana/KSM/operator on worker-2, node-exporter x6, 20Gi Longhorn PVC healthy with backup opt-out label; 62 of 66 targets up, 4 physical hosts down, same on gen2; 8 gitops-managed dashboards; alertmanager stays disabled as on gen2) **kube-prometheus-stack**: Longhorn PVC (fresh start; no restore), k3s control-plane scrape adjustments (disable kubeEtcd/scheduler/controller-manager ServiceMonitors or point at k3s metrics), Grafana dashboards (gitops-tagged per docs/claude-sessions), alerts routing. Grafana on gen3 reachable only via `--resolve` until DNS flip.
- [x] (2026-11-08: decided NO federation/remote scraping; gen3 Prometheus starts fresh, gen2 Prometheus stays until retirement) Decide Prometheus remote scraping of gen2 during overlap (optional): keep gen2 Prometheus until retirement.

### Phase 5 — DNS prep (session 7) — DONE 2026-11-08 — no user-visible change (merges 0f7c5c3 gen2, d1857a2 gen3 external-dns, 32d52e0 Grafana secret, 7848304 prometheus record)
_Prerequisites and open items: see "Loose ends and handoff after Phase 4" below the checklist (incl. Longhorn UI route, Grafana password, upsert-only before gen3 external-dns)._
- [x] (2026-11-08, main@0f7c5c3: pihole instance now `--policy=upsert-only`; Cloudflare instance left `sync` on purpose, it uses `registry: txt` owner `prod-gen2` so it only deletes its own records; Pi-hole A list 45 records identical to the pre-change baseline, pod 0 restarts, no errors) gen2 PR: Pi-hole external-dns `policy: sync` → `upsert-only` (both pihole + verify cloudflare instance policy); confirm gen2 records unaffected.
- [x] (2026-11-08, main@d1857a2: HR external-dns-pihole Ready, upsert-only/noop, owner `prod-gen3-pihole`, creds = existing Homelab item `pihole.local.abbottland.io (bananapi)` via base OnePasswordItem, nothing new in 1Password; one labelled route, `podinfo-gen3.local`; log "add podinfo-gen3.local.abbottland.io IN A -> 192.168.6.29"; Pi-hole list 45 -> 46, nothing removed, gen2 records unchanged) Deploy **pihole external-dns on gen3** with `upsert-only`, `registry: noop`, label `pihole-dns-enabled`, Pi-hole creds from 1Password. Initially no labelled routes on gen3 other than a test host (e.g. `podinfo-gen3.local.abbottland.io`).
- [x] (2026-11-08, main@d1857a2: HR Ready, deployment 0/0 via postRenderer (chart 1.15.0 hardcodes replicas: 1) plus `--dry-run`, owner `prod-gen3`, token Secret present, no `external-dns-enabled` routes) Deploy **Cloudflare external-dns on gen3** but with `--dry-run`/no `external-dns-enabled` routes (or zero replicas) until public cutover.
- [x] (2026-11-08: gen3 `infra/prod-gen3/pihole` = namespace + Service + EndpointSlice only; HTTPRoutes deleted until Phase 6) Confirm Pi-hole (bananapi) itself stays out of k8s cutover: the in-cluster `pihole` app in `infra/base/pihole` (EndpointSlice proxy to bananapi) — move with ingress, no data.
- [x] (2026-11-08: LAN `getent`, `dig @192.168.4.144` -> 192.168.6.29, https 200; Tailscale check done by user; Pi-hole list 45 -> 47 (podinfo-gen3, prometheus-gen3), gen2 records unchanged) Verify `podinfo-gen3` resolves to `.29` from LAN and Tailscale; gen2 records unchanged.

### Phase 6 — Wave 1 apps: stateless / LAN-only (sessions 8–9) — 6a DONE 2026-11-08; 6b/6c open
Move each = remove from `applications/prod-gen2/kustomization.yaml`, add to `applications/prod-gen3/kustomization.yaml`, reconcile, verify, check DNS flipped. Sub-sessions: 6a proxy apps, 6b dashy + flux UI/MCP + mcp-grafana + prometheus/grafana flip, 6c pihole routes (last).
- [x] (6a, 2026-11-08: staged unlabelled in c32de0e, tested with `--resolve`; flipped proxmox 4acaa51, asustor 37d3d63, haproxy ad9f88b, plex 076d29c, each its own approved merge; Pi-hole list 47 records, proxmox/asustor/haproxy now .29, `nas.local` unchanged at 192.168.4.124; gen2 `proxmox`, `asustor`, `haproxy`, `plex` namespaces pruned) proxmox (+ Istio DestinationRule), asustor (+ `nas` DNSEndpoint, gen3 `crd` source works), haproxy (stats proxy; EndpointSlice stays on `.28:8404` until .28 retires, update to `.29` stats at Phase 9), plex (EndpointSlice only).
- [ ] dashy (local chart via GitRepository; base chart template hardcodes `pihole-dns-enabled`, so staging on gen3 needs a HelmRelease postRenderer that removes the label; review per-cluster URL list), mcp-grafana (gen3 overlay with its own Homelab item `mcp-grafana-gen3`, token from gen3 Grafana)
- [ ] 6b: flip `prometheus.local` / `grafana.local` to gen3 (separate unlabelled `*-gen3` routes; gen2 UI routes renamed `prometheus-gen2.local` / `grafana-gen2.local`, show the gen2 diff first)
- [ ] pihole proxy route (`infra/base/pihole` HTTPRoute -> bananapi `.144:8081`) -> gen3 (6c, last)
- [ ] flux-operator web UI HTTPRoute + `flux-gitops` (flux-operator-mcp) -> gen3 (`03-flux-gitops-ks`, no `fluxinstance.yaml`). Gen2's `flux.local` route comes from the flux-operator HelmRelease (`infra/prod-gen2/flux-operator`, `web.httpRoute`), gen3's flux-operator is Ansible Helm without a route, so gen3 needs a standalone HTTPRoute to svc `flux-operator:9080`; the MCP HelmRelease `dependsOn: flux-operator` must be patched out on gen3 (no such HR there).
- [ ] Note: `home-assistant` is a proxy to `192.168.4.24` but public (`homeassistant.abbottland.io`, Cloudflare) → belongs to the public cutover (Phase 8), not here.

### Phase 7 — Wave 2 apps: stateful (sessions 10–13, one logical group per session)
- [ ] **media** stack (sonarr, radarr, prowlarr, qbittorrent, gluetun): 5 config PVCs restore via `longhorn-restore.sh` (sonarr/radarr/qbit 5Gi, prowlarr 2Gi, gluetun 1Gi; pre-create PVC before enabling app); `media-pv`/`media-pvc` (`manual`, RWX 10Ti, `/volume1/Media`) re-created from base manifests, no data move; NAS Postgres shared — gen2 scaled to 0 first. Verify VPN (gluetun) works from gen3 node network. Runbook: `docs/ai-reference-gen3-data-move.md`.
- [ ] **home-hud** (backup/media NFS PVs `/volume1/Dump` + `/volume1/Media` re-created from base manifests, no data move; NAS Postgres), **coder** (NAS Postgres; workspace home volume starts empty), **openclaw** (restore `openclaw-pvc` 10Gi via script).
- [ ] **harbor** + **harbor-cleanup** (registry on NFS PVC `nas-storage`, DB/Redis on NAS indexes 3,4,5,6,11,12 — only one cluster at a time; in-cluster Longhorn piece per helmrelease l.61/63). Data: restore `data-harbor-trivy-0` (5Gi) and `harbor-jobservice` (1Gi) with pre-created PVCs; registry dir (264 GB, 50Gi PVC) is rsynced on the NAS from `ClusterStorage/prod-gen2/harbor-harbor-registry-nas` into the gen3 provisioner dir with Harbor at 0 on gen2 (never a static PV at the gen2 path, see Appendix B). Check CI/ARC and other clusters pull from Harbor during outage; regcred secret.
- [ ] **arc** runners + cache server (needs Harbor, 1Password GH PAT; turbo-cache, actions-cache-server and arc-pnpm-store (nas-storage, not Longhorn) all start empty, no restore); check memory limits on 16GB workers.
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

### Loose ends and handoff after Phase 6a (2026-11-08) — READ FIRST in the next session
State: gen3 = 6 nodes Ready, 16 HelmReleases + crds/infra/apps-ks Ready, main@076d29c (plus doc commits). Phase 6a moved proxmox, asustor, haproxy, plex to gen3 (gen2 namespaces pruned). Gen3 Pi-hole external-dns is live (`upsert-only`, owner `prod-gen3-pihole`); the Cloudflare instance is dormant (0 replicas + `--dry-run`). Pi-hole has 47 A records: `proxmox`, `asustor`, `haproxy`, `podinfo-gen3`, `prometheus-gen3` at 192.168.6.29, the rest of gen2's at .28 (`nas.local` at 192.168.4.124). Still on gen2 and next: dashy, mcp-grafana, flux UI + MCP (6b), prometheus/grafana flip (6b), pihole routes (6c). No DNS for `grafana-gen3.local` or `podinfo-gen3.abbottland.io`: use `curl --resolve`.

**Open items, by when they bite**
- Phase 5 (DNS):
  - DONE in Phase 5: gen2 and gen3 Pi-hole external-dns are both `upsert-only`. Consequence: deleting a route/app on gen2 no longer removes its A record. Per-app flip = remove from gen2, enable on gen3 (gen3 upsert overwrites the IP, not yet exercised on a real record: verify on the first Phase 6 app); stale records need manual cleanup (`ai-reference-pihole-api.md`). Flip both back to `sync` only at Phase 9.
  - Longhorn UI HTTPRoute is still deleted on gen3 (decided Phase 5: no record wanted yet). Re-add as `longhorn-gen3.local...` with a label if the UI is needed, or at Phase 9 with the real hostname.
  - Base HTTPRoutes carry `pihole-dns-enabled` + a `.28` target annotation. Gen3 overlays strip the annotation everywhere; the label is kept only on podinfo-gen3.local and prometheus-gen3.local, stripped on grafana. Rule for new gen3 routes: add the label on purpose, one at a time; hostnames identical to gen2's must NOT be labelled until that app is removed from gen2.
  - Gen3 internal Gateway target is already `192.168.6.29` (annotation in `infra/prod-gen3/istio`). Public Gateway target stays `abbottland.io` (CNAME); no cloudflare external-dns on gen3 until Phase 8.
  - Records now: `podinfo-gen3.local`, `prometheus-gen3.local` (live). `grafana-gen3` and `longhorn-gen3`: no record by choice. Decide whether to keep the `*-gen3` records at Phase 9 (upsert-only: they will not delete themselves; remove via Pi-hole API).
  - Gen3 `upsert-only` overwrite of an existing gen2 record (.28 -> .29): worked unaided for asustor and haproxy, failed once for proxmox (cause unknown, needed a manual record delete); see Phase 6a learnings. Check every record after each flip.
  - gen2 `.local.non-prod.abbottland.io` records (13) are stale leftovers in Pi-hole; harmless, not touched. `nas.local` now comes from the gen3 DNSEndpoint `asustor/nas` (moved in 6a, record unchanged at 192.168.4.124).
  - Gen2 external-dns pods restart often (134 / 107 in 118 days, pre-existing, not from Phase 5). Investigated read-only 2026-11-08, no changes made, harmless so far: v0.15.0 exits on any provider/DNS error and the Pi-hole host is intermittently unreachable. Findings and undecided fixes: [`docs/incidents/2026-11-08-prod-gen2-external-dns-restarts.md`](../incidents/2026-11-08-prod-gen2-external-dns-restarts.md). Gen3's Cloudflare instance (Phase 8) may share the exposure.
  - Shared Pi-hole admin password: both clusters use the same Homelab item (`pihole.local.abbottland.io (bananapi)`); rotate it and both OnePasswordItems follow (auto-restart is NOT set on the pihole item, so restart the external-dns pods).
  - Dev-shell notes: reading Homelab items with `op item get <title> --vault Homelab --format json` works (Connect mode needs `--format json`). The record-list baseline file lived in the session scratchpad only; recreate it with the Pi-hole API (`ai-reference-pihole-api.md`) before any future change.
  - Phase 6 must re-add the pihole HTTPRoutes (deleted in `infra/prod-gen3/pihole`) when `pihole.local` moves; the Service/EndpointSlice already exist.
  - Phase 8: gen2 owns its Cloudflare CNAMEs via txt owner `prod-gen2`; gen3's Cloudflare instance uses owner `prod-gen3` and will NOT adopt them. Set gen3's `txtOwnerId` to `prod-gen2` (after stopping gen2's) or recreate the records. Then drop `--dry-run` and the 0-replica postRenderer in `infra/prod-gen3/external-dns`.
- Grafana admin password: DONE in Phase 5 (main@32d52e0), now from Homelab item `grafana-gen3-admin` via OnePasswordItem `grafana-admin`; `admin:admin` returns 401. Grafana still has no DNS record.
- Phase 8 (public cutover): the `letsencrypt-prod` ClusterIssuer is deleted on gen3 (overlay `$patch: delete`); re-add it and flip the Gateway `cert-manager.io/cluster-issuer` annotations from staging. Certs are all staging now (browsers warn). Both clusters issuing identical names hits the 5/week duplicate limit.
- Not scraped: k3s control plane (etcd/scheduler/controller-manager) and kube-proxy; would need `kube-*-arg bind-address` in `home-playbooks/playbooks/kubernetes-gen3`. Alertmanager is disabled (like gen2): there is no alert routing at all.
- Dead scrape targets (down on gen2 too): homeassistant 192.168.4.37, dumbledore .4.157, marauders-map 192.168.5.91, elderwand 192.168.5.142. Fix or drop at gen2 retirement.
- Dashboards for harbor, arc, home-hud, etc. exist but are empty until those apps move.
- HAProxy .29: HTTP backends k3sw1/k3sw2 only (not worker-3 .46); HTTPS is tcp mode with no health check, so it shows UP regardless. Source ACL = LAN 192.168.4.0/22 + Cloudflare ranges (verify refresh at Phase 8).
- Capacity: controller-3 has ~3 GB allocatable (64% used) and controllers are untainted; Prometheus/Grafana are pinned to workers by nodeAffinity. Worker-3 is 6 GB. Watch Harbor/ARC/Prometheus memory in Phase 7.
- Shared Connect identity: gen3 `op-credentials` was re-sealed from the live gen2 secret, so gen2 and gen3 share one Connect server identity (own server per cluster is the alternative). Sealed-secrets controller key backup lives in 1Password (`sealed-secrets-key-prod-gen3`).
- Intentional leftovers: Longhorn BackupTargets `rehearsal-copy` (safety copy) and `live-restore` (live gen2 store, read-only in practice), both idle; gen2 Snapshot `data-move-final-1711` and Backup `data-move-final-prowlarr` (deleting the Backup CR deletes it from the store: user's call). Never point gen3 at `longhorn-prod` for writes. Data-move gaps: `docs/ai-reference-gen3-data-move.md` "Known gaps / loose ends".
- Git hygiene: stale remote branches (e.g. `phase4-istio`, `phase3-*`, `gen3-phase2-*`, `phase5-gen2-upsert-only`, `phase5-gen3-external-dns`, `phase5-grafana-admin`, `phase5-prometheus-record`, `phase5-docs`, `phase5-docs-final`) remain on origin; deleted so far: `phase4b-prometheus`. All Phase 5 branches were fast-forward merged to main.

**Gotchas that cost time in Phase 4 (keep in mind)**
- gen3 CNI is Calico: istio-cni uses chart-default paths; k3s flannel paths do not apply. ztunnel needs `IPV6_ENABLED=false` (nodes have no IPv6).
- A HelmRelease stuck in `install` blocks until its 5m timeout, then retries as upgrade with new values; `flux reconcile ks` may hit the CLI timeout (harmless). infra-ks has `wait: true`.
- `kubectl kustomize applications/prod-gen3` needs `--load-restrictor LoadRestrictionsNone`; infra and clusters render without it.
- Process: work on a branch, every merge/push to main needs the user's explicit approval each time (the auto-mode classifier blocks pushes to main otherwise). home-kubernetes has no pre-commit config; verify with `kubectl kustomize` and yamllint (style warnings only) and say so.

### Phase 6a learnings — proxy apps (2026-11-08)
- Staging pattern: gen3 overlay per app references the base DIRECTORY, replaces the hostname, and removes the label and `.28` target annotation with JSON patches; the flip merge deletes those patches AND removes the app from `applications/prod-gen2` (one merge). The `*-http-to-https` routes are unlabelled and never create records.
- Gen3 `upsert-only` DOES overwrite an existing A record (.28 -> .29), delete+create, typically in the first ~1 min cycle after the labelled route exists: asustor and haproxy did it unaided. **proxmox did not**: gen3 logged "All records are already up to date" for ~3 cycles while the record stayed .28 (gen2 route already pruned, so the UI was down ~4 min); a single Pi-hole API delete of that record made gen3 recreate it as .29 on the next cycle. Cause NOT found. Disproven: `--txt-owner-id` (throwaway tests `ownertest`/`ownertest2` with owner id set, a record pre-seeded at .28 and a labelled route: overwritten in one cycle, also in a long-running pod), route Accepted status timing (Accepted at creation). Fallback stays: after gen2 prunes the route, if the record is not .29 within 2 cycles, delete the old record via the Pi-hole API.
- Pi-hole's DNS port (53) refuses connections for ~5-10 s after every custom-list change (dnsmasq reload). Expect a short blip per record write/delete, and poll `dig` instead of assuming failure.
- Removing an app from `applications/prod-gen2` prunes its namespace on gen2; reconcile gen2 first (`flux --context prod-gen2 reconcile ks apps-ks --with-source`), then gen3. Flip downtime for LAN UIs was ~1-2 min (proxmox ~4 min).
- Gen3 external-dns logs a harmless "Could not update ObservedGeneration of the CRD: dnsendpoints.externaldns.k8s.io "nas" not found" warning each cycle for the `nas` DNSEndpoint; the `nas.local` record is unaffected.
- `--log-level=debug` on the Pi-hole instance shows per-route endpoint generation; it was set by a live `kubectl patch` during the experiment and reverted to info (a Helm upgrade would also revert it).
- zsh gotcha: `echo == $c` fails ("= not found"); quote the string.
- Verification baseline kept in the session scratchpad only (`pihole-baseline.tsv`); recreate with the Pi-hole API before the next change.

### Phase 5 learnings — DNS prep (2026-11-08)
- Order mattered: gen2 `upsert-only` merged and verified (args, logs, record list identical to a saved baseline) before gen3's instance existed. Two merges: gen2 (0f7c5c3), gen3 (d1857a2).
- Baseline method (read-only): Pi-hole v5 auth = sha256(sha256(pw)); from the dev shell Pi-hole `192.168.4.144:8081` is reachable directly, no debug pod needed. The password comes from `op item get "pihole.local.abbottland.io (bananapi)" --vault Homelab --format json` (Connect mode requires `--format json`). Diff the `customdns` list before/after.
- Gen3 reused the existing Homelab items (Pi-hole, Cloudflare token) through the base OnePasswordItems: no manual 1Password work for external-dns.
- external-dns chart 1.15.0 has no `replicaCount` (Deployment hardcodes `replicas: 1`), so the dormant Cloudflare instance is scaled to 0 with a HelmRelease `postRenderers` kustomize patch, plus `--dry-run` so a later scale-up cannot write.
- The base pihole HelmRelease talks to `pihole.pihole.svc:8081`, so gen3 needs the pihole Service/EndpointSlice even without the proxy routes.
- Grafana admin: Homelab item `grafana-gen3-admin` (username/password fields; the operator maps field labels to Secret keys, so the chart uses `userKey: username`, `passwordKey: password`) -> OnePasswordItem `grafana-admin` -> `grafana.admin.existingSecret`. Verified `admin:admin` = 401, new login 200, 8 gitops dashboards intact. Adding the second record (prometheus-gen3) was a one-line patch edit; gen2 stayed unchanged (47 records = 45 + 2).
- Longhorn UI route intentionally still deleted on gen3 (no record wanted); Grafana has no record.
- Record appeared ~1 min after the route was synced (one interval). Target came from the Gateway annotation (`192.168.6.29`).

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

- Longhorn installed 2026-11-08 (same session, user-approved): test PVC (1Gi, 2 replicas on worker-1/-3) wrote data, snapshot + backup Completed in `longhorn-prod-gen3`, then deleted (BackupVolume CR removed by hand; store back to 0 files). Chart gotchas: backup target lives under `defaultBackupStore`, not `defaultSettings`; StorageClass replicas come from `persistence.defaultClassReplicaCount` (default 3), not the default setting. Longhorn `Backup` CR needs the `backup-volume` label when created by hand.
- Per-app data move procedure: done later the same day (see Data move learnings). Temporary BackupTarget `rehearsal-copy` (safety copy) intentionally left in place, idle.

- Restore recipe (works in Longhorn 1.9.2, no UI needed): (1) `BackupTarget` CR in `longhorn-system` with `backupTargetURL` of the store and `pollInterval: 0s`, patch `spec.syncRequestedAt` to force a sync; BackupVolumes then appear with `KubernetesStatus` labels (ns/pvc names). (2) `Volume` CR: `size` (bytes, string), `numberOfReplicas: 2`, `frontend: blockdev`, `fromBackup: nfs://<server>:<path>?backup=<backup-name>&volume=<original pvc-... volume name>`; wait for `status.restoreRequired=false`. (3) static PV: `csi.driver: driver.longhorn.io`, `volumeHandle: <Volume name>`, `fsType: ext4`, `storageClassName: longhorn-static`, `claimRef` to the target PVC; PVC with `volumeName` set. This is also the per-app data move procedure (restore from the LIVE gen2 store only via a fresh final backup, using a read-only-in-practice temporary target; never add recurring jobs to it).
- Deleting a `BackupTarget` CR may delete backups in the remote store (unverified); do not delete one that points at a store you want to keep.

### Phase 4 learnings — istio (2026-11-08)
- Three merges were needed (f97eecb, 66e0b2f, aa237d0) because the first one shipped k3s CNI paths. Routes needed Gateways, so they were a separate last merge.
- **istio-cni paths: do NOT use the k3s paths on gen3.** Gen3 runs Calico (tigera operator, k3s flannel disabled): `10-calico.conflist` lives in `/etc/cni/net.d`, binaries in `/opt/cni/bin`; `/var/lib/rancher/k3s/agent/etc/cni/net.d` is empty. With k3s paths istio-cni logs "no networks found" and never becomes Ready. The chart defaults are correct. (The handover note's k3s paths apply to flannel clusters.)
- **ztunnel needs `env.IPV6_ENABLED: "false"`**: gen3 nodes have no IPv6 in the kernel (`/proc/net/if_inet6` missing); without it ztunnel crashes with "readiness server starts: Address family not supported".
- A HelmRelease stuck in its first `install` (cni) blocks until its 5m timeout, then retries as upgrade with the new values; `flux reconcile ks infra-ks` alone waits that out. infra-ks (5m timeout) reported Unknown meanwhile, and `flux reconcile` hit the CLI timeout; harmless.
- `internal-apps-ip-allowlist` needed no change (192.168.0.0/16 covers HAProxy .29 and LAN, 10.244/16 pod CIDR, 10.0.0.0/8 covers service CIDR). Verified by a 200 from a LAN client on the `*.local.*` host.
- Base gen2 listener[1] patch is a no-op against current base; only the apex listener patch was ported. Gateway annotations: both issuers -> letsencrypt-staging; internal Gateway target -> 192.168.6.29; public Gateway keeps CNAME target `abbottland.io` (no .28 involved, no external-dns on gen3).
- Gen3 podinfo routes are local files with `podinfo-gen3` hostnames and NO `pihole-dns-enabled` / `external-dns-enabled` labels; checked: no labelled route and no external-dns pod on gen3. Reach via `curl --resolve podinfo-gen3.local.abbottland.io:443:192.168.6.29`.
- `kubectl kustomize applications/prod-gen3` needs `--load-restrictor LoadRestrictionsNone` (podinfo overlay references base files; Flux is fine with it). infra and clusters render without it.
- Longhorn UI HTTPRoute stays deleted: it needs a Pi-hole record and `longhorn.local.abbottland.io` collides with gen2. Re-enable in Phase 5 with a gen3 hostname.
- HAProxy .29: HTTP backends k3sw1/k3sw2 UP (stats :8404); HTTPS is tcp mode with no health check. Worker-3 (.46) is not a backend.

### Phase 4b proposal — kube-prometheus-stack (next session)
- Overlay `infra/prod-gen3/kube-prometheus-stack` from `base/kube-prometheus-stack` (gen2 overlay as template): `externalLabels.cluster: prod-gen3`; fresh 20Gi Longhorn PVC with label `recurring-job-group.longhorn.io/default: disabled` (skip daily-backups); routes with `*-gen3.local.abbottland.io` hostnames and no DNS labels.
- Control plane: base already disables kubeEtcd/Scheduler/ControllerManager/Proxy, so nothing to change now; scraping k3s control-plane metrics needs `--kube-*-arg=bind-address=0.0.0.0` in the k3s playbook, so defer. Consider disabling matching default rule groups to avoid noise.
- Drop or keep gen2-only physical node/windows scrapeconfigs; check dashboards carry the `gitops-managed` tag; Grafana/alert secrets via OnePasswordItem; set Prometheus resources/retention for 16/16/6 GB workers; istio PodMonitors/ServiceMonitors start scraping automatically.
- Check that the istiod/ztunnel/ingress monitors don't alert before first scrape; Longhorn ServiceMonitor likewise.

### Phase 4b learnings — kube-prometheus-stack (2026-11-08)
- One merge was enough (CRDs HR, namespace and Gateways already existed). The stack came up in ~1 min; no infra-ks timeout this time.
- Control-plane scrapes stay off (base): disabled flags also drop the etcd/scheduler/controller-manager/kube-proxy rule groups, so nothing sits permanently down. Scraping k3s's single-process control plane needs `kube-*-arg bind-address` in the k3s playbook (not done).
- Overlay: `externalLabels.cluster: prod-gen3`, Prometheus + Grafana pinned off control planes via nodeAffinity (controller-3 has ~3 GB), routes `grafana-gen3` / `prometheus-gen3.local.abbottland.io` with the `pihole-dns-enabled` label and external-dns annotation removed by JSON patch. Verified: no labelled routes, names do not resolve. Grafana admin is still base `admin` (LAN-only via `--resolve`), move to a OnePasswordItem before the DNS phase.
- Physical-host ScrapeConfigs were copied from gen2. Down on both clusters (not a gen3 network issue): homeassistant 192.168.4.37 (refused), dumbledore .4.157 (offline), marauders-map 192.168.5.91, elderwand 192.168.5.142 (no route/off). The three up from gen3: room_of_requirement, bananapi, chimaera. Fix or drop the dead ones at retirement.
- Test: `curl -sk --resolve prometheus-gen3.local.abbottland.io:443:192.168.6.29 https://prometheus-gen3.local.abbottland.io/api/v1/targets`; Grafana `/api/health` 200, `/api/search?tag=gitops-managed` returns 8 (admin:admin).

### Phase 3b plan — Longhorn (DONE 2026-11-08, incl. per-app move procedure; see `docs/ai-reference-gen3-data-move.md`)
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

---

## Appendix B — Volume inventory (prod-gen2, verified 2026-11-08 via kubectl)

LH = Longhorn (gen2 reclaim `Delete`, 3 replicas on gen2, 2 on gen3). Restore = `scripts/longhorn-restore.sh`; full steps in `docs/ai-reference-gen3-data-move.md`.

| gen2 ns/PVC | App | Class, mode, size | gen3 decision | Method |
|---|---|---|---|---|
| arc-runners/turbo-cache-storage | arc turbo cache | LH RWO 20Gi | EMPTY | app manifest provisions fresh |
| arc-runners/actions-cache-server-data | arc | LH RWO 30Gi | EMPTY | HelmRelease provisions fresh |
| arc-runners/arc-pnpm-store | arc | nas-storage RWX 20Gi | EMPTY | fresh PVC (`prod-gen3` dir). Stale Longhorn backup from July is ignored |
| kube-prometheus-stack/prometheus-…-0 | Prometheus | LH RWO 20Gi | EMPTY | chart template (Phase 4) |
| coder-workspaces/coder-…-home | coder workspace | LH RWO 20Gi (detached, backup 2026-07-23) | EMPTY | terraform recreates |
| openclaw/openclaw-pvc | openclaw | LH RWO 10Gi | RESTORE | script; PVC name `openclaw-pvc`, class `longhorn` |
| media/sonarr-config, radarr-config, qbit-config | media | LH RWO 5Gi each | RESTORE | script |
| media/prowlarr-config | media | LH RWO 2Gi | RESTORE | script (dry-run subject, done) |
| media/gluetun-config | media | LH RWO 1Gi | RESTORE | script |
| harbor/data-harbor-trivy-0 | harbor trivy (StatefulSet) | LH RWO 5Gi | RESTORE | script; pre-create PVC with the exact template name before enabling |
| harbor/harbor-jobservice | harbor | LH RWO 1Gi | RESTORE | script; pre-create before enabling |
| harbor/harbor-registry-nas | harbor registry | nas-storage RWX 50Gi (264 GB actually used; NFS has no quota) | COPY DATA | NAS-side rsync, see below |
| media/media-pvc, home-hud/media-pvc | media, home-hud | `manual` RWX 10Ti, NFS `/volume1/Media`, PV Retain | no data | re-create PV+PVC from base manifests on gen3 (media PV has no claimRef/volumeName, binds by class+size; home-hud uses claimRef + volumeName) |
| home-hud/backup-pvc | home-hud | `manual` RWX 10Ti, NFS `/volume1/Dump` | no data | same |

**harbor-registry-nas method: rsync on the NAS into the gen3 dir (recommended).**
- Static PV at the gen2 path rejected: gen2's PVC is reclaim `Delete` with `archiveOnDelete: 'true'`, so the final "delete from gen2" step renames the directory under gen3's feet, and gen3 would write into the only copy (no rollback). It also breaks the one-subdir-per-cluster convention.
- Procedure: Harbor scaled to 0 on gen2 (Postgres metadata must match blobs), let the gen3 PVC be provisioned (app suspended/at 0) so the provisioner creates `/volume1/ClusterStorage/prod-gen3/harbor-harbor-registry-nas`, then on the NAS: `rsync -a --info=progress2 /volume1/ClusterStorage/prod-gen2/harbor-harbor-registry-nas/ /volume1/ClusterStorage/prod-gen3/harbor-harbor-registry-nas/` (user runs it or approves it). 17 TB free on /volume1; a warm pre-copy while Harbor runs is fine, then a final delta at scale-0. Verify with `rsync -an --stats` (no changes) and matching `du`/file count. Rollback: delete the gen3 dir (by hand), gen2 untouched.
- Fallback if the dir name differs: static NFS PV at the gen3 path with a claimRef to `harbor/harbor-registry-nas`.

**10Ti `manual` PVs** (media, home-hud): no data move; the same NAS paths are mounted by both clusters, so the only rule is "one cluster at a time" (gen2 scaled to 0 first).

## Data move learnings (2026-11-08)
- The gen3 `rehearsal-copy` target already mirrors all 12 gen2 BackupVolumes/Backups (92 Backup CRs). The `volume=` part of `fromBackup` is the ORIGINAL gen2 `pvc-<uuid>` name, not the gen3 BackupVolume CR name (which has a different suffix).
- Dry-run `media/prowlarr-config` (2Gi, backup-3fbc8790785843ae from the copy) into scratch ns `data-move-test`: restore finished in about 30 s, PV/PVC Bound, read-only pod saw 692 files/90.1M (`config.xml` present). NAS check before/after on `longhorn-prod` (46,853 files, 43,531 dirs, newest mtime 1794107070), `.pre-gen3-copy` (47,999 / 44,425) and `longhorn-prod-gen3` (0 files): identical, 0 files modified in the last 30 min. Cleanup via `--cleanup` removed only PVC/PV/Volume; `rehearsal-copy` and all Backup CRs untouched.
- Binding: pre-bound PV `storageClassName` must equal the app manifest's (`longhorn`), otherwise Flux's apply fails (spec immutable on a bound PVC). Pre-create with its OWN server-side-apply field manager: a PVC created by client-side `kubectl apply` then adopted by `kustomize-controller` makes Flux own `volumeName`, and its next apply (manifest has no `volumeName`) fails with "spec is immutable". With a separate manager, Flux's SSA is idempotent and `volumeName` stays. Larger size accepted (would expand), smaller/other accessModes rejected.
- BusyBox `find` on the NAS has no `-printf`; use `stat -c '%Y %n'`. NAS TZ is US Central (CST), mtimes there are UTC-6 in `date` output.
- gen2 LH volumes are all `Delete` reclaim: deleting the gen2 PVC at the end deletes the volume, so keep the final backup and soak before deleting.
- LIVE-store restore verified (17:11-17:16 UTC, outside gen2's 03:00 job): live `longhorn-prod` before = 46,853 files/43,531 dirs/newest 1794107070. The one approved gen2 backup (manual Snapshot CR `data-move-final-1711` then Backup CR `data-move-final-prowlarr` on gen2, ~2 s, 530 MB) added exactly +19 files/+21 dirs (46,872/43,552, newest 1794157921). Creating+syncing the `live-restore` BackupTarget (pollInterval 0s) and the restore (692 files) changed nothing further (counts, newest mtime identical; safety copy and `longhorn-prod-gen3` identical too). So a gen3 target on the live path is read-only in practice.
- Leftovers by design: gen3 target `live-restore` (idle, same as `rehearsal-copy`), gen2 Snapshot `data-move-final-1711` + Backup `data-move-final-prowlarr` (test backup of prowlarr-config; deleting the Backup CR would delete it from the store, so removal is the user's call). `live-restore` also mirrored the live store's Backup CRs onto gen3.
- A manual gen2 backup = Snapshot CR (`spec.volume`, `createSnapshot: true`) then Backup CR with labels `backup-volume=<pvc-…>`, `backup-target=default` and `spec.snapshotName`; the backup name you choose becomes the name in the store URL (`backup=<name>`).
- zsh: pass script args as an array (`A=(...); cmd "${A[@]}"`); an unquoted `$A` is not word-split.
- Loose ends and untested parts (chart-created PVCs, Harbor rsync, app start-up on restored data, sync-before-restore, retention of manual backups) are listed in `docs/ai-reference-gen3-data-move.md` under "Known gaps / loose ends". Read it first if data looks wrong during Phase 7.
