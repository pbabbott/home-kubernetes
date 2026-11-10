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
| `02-apps-ks.yaml` | `./applications/<cluster>/` | infra-ks |

Add CRD-related material under `crds/<cluster>/` so it applies before infra and apps. Don't rely on app charts to own CRDs when this repo's layering should own the cluster API surface.

## Longhorn Backup Targets

NFS host: `192.168.4.124`, base export: `/volume1/Backups/`

| Cluster | Backup target |
| --- | --- |
| Prod gen 3 | `nfs://192.168.4.124:/volume1/Backups/longhorn-prod-gen3`. Worker nodes need a manual label, see `ai-reference-gen3-manual-steps.md` |
| Prod gen 2 (retired) | `nfs://192.168.4.124:/volume1/Backups/longhorn-prod`. Holds the final gen2 backups (`p7-final-*`, rollback for moved volumes); gen3 must never write to it. Delete only deliberately (issue #40) |
| Non-prod gen 2 (retired) | `nfs://192.168.4.124:/volume1/Backups/longhorn-nonprod` |

## Cluster Notes

- Workers run containerd
- SSH key auth only (no passwords)
- gen3 nodes have no IPv6
