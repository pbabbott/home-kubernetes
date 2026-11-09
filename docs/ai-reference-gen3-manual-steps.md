# Gen3 (prod-gen3) manual steps that are NOT in GitOps

Read this before adding/replacing a node, rebuilding gen3, or wondering why Longhorn has no disk on a node.
Things below live outside Git, so Flux will not recreate them.

## Joining a new worker (checklist)
1. Provision the VM and join k3s via `home-playbooks` (`playbooks/kubernetes-gen3/`, `terraform/hogwarts/`).
2. **Longhorn data disk:** worker needs a dedicated ext4 disk mounted at `/mnt/ssd` (existing workers: `/dev/sdb`, ~100G), plus `open-iscsi` with `iscsid` active and an NFS client (`mount.nfs`). Verify: `ssh firebolt@<ip> 'findmnt /mnt/ssd; systemctl is-active iscsid'`.
3. **Label the node so Longhorn creates its default disk** (REQUIRED, manual):
   ```
   kubectl --context prod-gen3 label node <node> node.longhorn.io/create-default-disk=true
   ```
   Why: `infra/prod-gen3/longhorn/longhorn-helmrelease-patch.yaml` sets `createDefaultDiskLabeledNodes: true`. Controllers are untainted and have no `/mnt/ssd`; without this setting Longhorn would put a disk on their root filesystem. Unlabeled node = Longhorn manager runs but has NO disk and holds no replicas (this is intended for controllers).
   Current labeled nodes: `tf-prod-k3s-worker-1`, `-2`, `-3` (labeled 2026-11-08). A re-created node loses the label and must be re-labeled.
4. Verify: `kubectl --context prod-gen3 -n longhorn-system get nodes.longhorn.io` (node Ready, schedulable, disk at `/mnt/ssd`).
5. Replica count is 2 (default setting and StorageClass); revisit if worker count changes.
6. Arch: Longhorn is pinned to `kubernetes.io/arch: amd64`; arm nodes (e.g. dumbledore) get no Longhorn.

## NAS-side directories (created by hand on room_of_requirement, 192.168.4.124; `ssh pabbott@192.168.4.124`, alias `ror`)
- `/volume1/ClusterStorage/prod-gen3`: nas-storage provisioner root; must exist or the provisioner pod fails to mount. Deleted PVCs leave `archived-*` dirs here (`archiveOnDelete: 'true'`); clean up by hand.
- `/volume1/Backups/longhorn-prod-gen3`: gen3's own Longhorn backup target. NEVER point gen3 at `longhorn-prod` (gen2's live store) or `longhorn-prod.pre-gen3-copy` (safety copy).
- NFS export rules (`/etc/exports`) already allow `192.168.0.0/16` rw no_root_squash; no per-node NAS change needed.

## Secrets / 1Password (see `ai-reference-secrets.md`)
- `op-credentials` is the only SealedSecret; sealed with the gen3 controller key (backup: 1Password Secure Note `sealed-secrets-key-prod-gen3`). On rebuild restore the key BEFORE Flux installs the controller.
- Anything written to 1Password is done by hand in the UI (dev-shell Connect token is read-only).
- Grafana admin login: Homelab item `grafana-gen3-admin` (created by hand; fields `username`, `password`) -> OnePasswordItem `grafana-admin` in ns `kube-prometheus-stack` -> chart `grafana.admin.existingSecret`. Missing item = Grafana pod stuck on a missing Secret.
- mcp-grafana token: Homelab item `mcp-grafana-gen3` with ONE concealed field `GRAFANA_SERVICE_ACCOUNT_TOKEN` (created by hand) -> OnePasswordItem `mcp-grafana-secrets` in ns `mcp-grafana` (gen3 overlay patches itemPath). Token = Viewer service account `mcp-grafana` in gen3 Grafana (token `mcp-grafana-gen3`, no expiry). A rebuilt gen3 Grafana loses the account: recreate it and update the item.
- Longhorn `cifs-secret` OnePasswordItem is the same Homelab item as gen2; it is probably unused for `nfs://` targets.

## Ingress testing (no DNS yet)
Phase 4 added istio; no manual cluster step. Gen3 has no DNS records, so test with `curl --resolve <host>:443:192.168.6.29 https://<host>/` (`-k`: staging cert is untrusted). Do not add `pihole-dns-enabled` / `external-dns-enabled` labels to gen3 routes before Phase 5.
Rebuild notes: gen3 uses Calico, so istio-cni needs the chart-default CNI paths, and ztunnel needs `IPV6_ENABLED=false` (nodes without IPv6); both are already in `infra/prod-gen3/istio`.

## Monitoring (kube-prometheus-stack on gen3)
No manual cluster step. Grafana admin credentials come from the 1Password item `grafana-gen3-admin` (see above); Grafana and Prometheus routes: Prometheus has a Pi-hole record once the Phase 5 `prometheus-gen3.local` merge is in, Grafana has none (reach it with `curl --resolve grafana-gen3.local.abbottland.io:443:192.168.6.29`). k3s control-plane metrics (etcd/scheduler/controller-manager) are intentionally not scraped: k3s runs them in one process and would need `kube-*-arg bind-address` flags in `home-playbooks/playbooks/kubernetes-gen3`.

## Media (Phase 7)
No cluster step beyond the data restore: create ns `media` by hand, then restore the 5 config PVCs (`sonarr-config`, `radarr-config`, `qbit-config`, `prowlarr-config`, `gluetun-config`) with `scripts/longhorn-restore.sh` BEFORE the app is in the gen3 overlay (see `ai-reference-gen3-data-move.md`). gluetun needs `/dev/net/tun` on the node (present on Ubuntu 24.04 workers) and PIA credentials from the existing Homelab item (`pia-credentials` OnePasswordItem); the NFS PV `media-pv` comes from the base manifest (`/volume1/Media`, no data move). Gen2's `media` PVCs must stay until the soak is over (reclaim Delete).

## home-hud, coder, openclaw (Phase 7 group 2)
Only `openclaw` needs a restore: create ns `openclaw` by hand, then `scripts/longhorn-restore.sh` for `openclaw-pvc` (10Gi, `longhorn`) from the final gen2 backup BEFORE the app is in the gen3 overlay; run it in the background (long restores outlive a short shell timeout, see the learnings). home-hud NFS PVs (`/volume1/Media`, `/volume1/Dump`) come from the base manifests; coder and home-hud use NAS Postgres (shared: run in one cluster only). openclaw's MCP servers are configured in the openclaw UI (not in git): `grafana-prod`, `flux-prod`, `arr`, `qbittorrent` (sse), `homelab-api`, URLs in the migration plan's loose ends register; repoint after any rebuild/restore of `openclaw-pvc`.

