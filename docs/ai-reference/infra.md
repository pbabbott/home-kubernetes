# Infrastructure Reference

## Clusters

- **Prod gen 3** (`prod-gen3`) — the only live cluster (k3s on `hogwarts`, plus controller-3 + worker-3 on `chimaera`)
- **Prod gen 2** (`prod-gen2`) and **Non-prod gen 2** (`non-prod-gen2`) — retired 2026-11-09. Flux suspended, VMs powered off, kept as rollback until ~2026-12-07, then destroyed (issue #40). Their overlays stay in this repo until then (issue #35)
- **Prod gen 1** — dead; only its code remains

Hosts, IPs, SSH users and VM IDs live in `home-playbooks/docs/HOSTS.md` (not repeated here, it goes stale). Kubeconfig contexts: `scripts/get-kubeconfig.sh` in the workspace repo (`prod-gen3`).

### Ingress (HAProxy)

HAProxy LXC `192.168.6.29` (on `hogwarts`) fronts the gen3 workers (NodePorts 30080/30443, PROXY v2). It serves both LAN and public traffic (eero forwards WAN 80/443 to it). Stats: [http://192.168.6.29:8404/](http://192.168.6.29:8404/). The gen2 HAProxy `.28` was destroyed.

## DNS and Ingress Hostnames

Wildcard patterns (HTTPRoute `hostnames`, TLS certs, split-horizon DNS):

| Pattern | Visibility |
| --- | --- |
| `*.abbottland.io` (and the apex) | Public (Cloudflare) |
| `*.local.abbottland.io` | Internal (Pi-hole) |

`*.local.*` = internal. Without `local` = public. The `*.non-prod.*` patterns belonged to non-prod gen2 and are unused.

## Flux Layering

Numbered `Kustomization` files under `clusters/<cluster>/`:

| File | Path | Depends on |
| --- | --- | --- |
| `00-crds-ks.yaml` | `./crds/<cluster>/` | — |
| `01-infra-ks.yaml` | `./infra/<cluster>/` | crds-ks |
| `02-apps-ks.yaml` | `./apps/<cluster>/` | infra-ks |

Add CRD-related material under `crds/<cluster>/` so it applies before infra and apps. Don't rely on app charts to own CRDs when this repo's layering should own the cluster API surface.

## Longhorn Backup Targets

NFS host: `192.168.4.124`, base export: `/volume1/Backups/`

| Cluster | Backup target |
| --- | --- |
| Prod gen 3 | `nfs://192.168.4.124:/volume1/Backups/longhorn-prod-gen3`. Worker nodes need a manual label, see `gen3-manual-steps.md` |
| Prod gen 2 (retired) | `nfs://192.168.4.124:/volume1/Backups/longhorn-prod`. Deleted 2026-11-11 (with `longhorn-prod.pre-gen3-copy`, the `live-restore`/`rehearsal-copy` BackupTargets and the `p7-final-*` Backups). The 8 restored gen3 volumes were switched to the `default` target first. Issue #40 |
| Non-prod gen 2 (retired) | `nfs://192.168.4.124:/volume1/Backups/longhorn-nonprod` |

## Longhorn replica policy (gen3, issue #59)

Three worker disks (~97 GiB each), over-provisioning 150%. Default class `longhorn` = 2 replicas; `longhorn-single` = 1 replica (defined in `infra/prod-gen3/storage/longhorn/`).

| Volume | Class | Why |
| --- | --- | --- |
| `arc-runners/actions-cache-server-data`, `turbo-cache-storage` | `longhorn-single` | CI caches, rebuild themselves |
| `kube-prometheus-stack` Prometheus | `longhorn-single` | Metrics, 3d retention, `retentionSize` 17GB; excluded from `daily-backups` by hand: the PVC-template label does not reach the Longhorn volume, so after recreating it run `kubectl -n longhorn-system label volumes.longhorn.io <vol> recurring-job-group.longhorn.io/default=disabled --overwrite` |
| harbor trivy + jobservice, media `*-config`, openclaw | `longhorn` (2) | Small, not regenerable (trivy is tiny; its StatefulSet claim is immutable) |

PVC `storageClassName` is immutable: moving an existing PVC to another class means deleting and recreating it. Replica count of an existing volume can also be patched live (`volumes.longhorn.io` `spec.numberOfReplicas`), but git only controls new PVCs.

## Cluster Notes

- Workers run containerd
- SSH key auth only (no passwords)
- gen3 nodes have no IPv6
