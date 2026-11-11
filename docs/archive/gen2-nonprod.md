# Gen 2 non-prod: `non-prod-gen2`

Tag `archive-gen2-nonprod` -> commit `c32de0ea63f537c4fcaa0be758e28f31e2924691`.
Removed paths: `clusters/non-prod-gen2/`, `crds/non-prod-gen2/`, `infra/non-prod-gen2/`, `apps/non-prod-gen2/`.
Last changed 2026-07-25 (`75b6609`, ARC base alignment).

## What it was
A smaller staging copy of prod-gen2 (first Flux commit 2026-03-22): kubeadm VMs on `chimaera` (`tf-nonprod-k8s-controller-1`,
`tf-nonprod-k8s-worker-1..3`), used to try changes before prod. Hostnames used the `non-prod` subdomain
(`*.non-prod.abbottland.io` public, `*.local.non-prod.abbottland.io` internal) and public non-prod URLs were removed 2026-05-16.
Powered off because `chimaera` ran out of resources, and never migrated to gen3 (gen3 has no non-prod cluster).
Hosts: `home-playbooks/docs/HOSTS.md`.

## Flux layout
Same pattern as prod: Flux Operator `FluxInstance`, then `00-crds-ks` -> `01-infra-ks` -> `02-apps-ks` -> `03-flux-gitops-ks`,
with thin overlays over `crds/base`, `infra/base` and `apps/base`. Rebuild gotchas are in
`docs/plans/2026-05-21-nonprod-gen2-cluster-rebuild-op-connect.md` and `docs/claude-sessions/2026-05-22-nonprod-gen2-rebuild-flux-recovery.md`.

## Infrastructure
| Component | Summary |
| --- | --- |
| crds | Same CRD set as prod (Istio, Gateway API, cert-manager, flux-operator, sealed-secrets, onepassword, kube-prometheus-stack, external-dns, longhorn). |
| flux-operator, sealed-secrets, onepassword, cert-manager, istio, nas-storage | Same installs as prod, via base with minimal overlays; `op-credentials` was a cluster-specific SealedSecret. |
| longhorn | Longhorn with its own backup target `longhorn-nonprod` on the NAS, a backup StorageClass, recurring job and UI route. |
| kube-prometheus-stack | Prometheus/Grafana stack with a values patch and dashboards. |
| external-dns | Cloudflare + Pi-hole instances filtered to the `non-prod` domains. |
| pihole | Proxy route to the Pi-hole admin UI. |
| metrics-server, priorityclass | Shared base. |

## Applications
| App | Summary |
| --- | --- |
| asustor | Proxy to the NAS admin UI. |
| dashy | Dashy dashboard with non-prod values (media/apps sections off). |
| haproxy | Proxy to the HAProxy stats page. |
| harbor | A Harbor registry instance on non-prod. |
| plex | Proxy to Plex on the NAS. |
| podinfo | Test app for routing/cert checks. |
| proxmox | Proxy route to the Proxmox UI. |
| arc | Overlay existed but was disabled in `apps/non-prod-gen2/kustomization.yaml` (cluster not running ARC runners). |

## Restoring it
`git checkout archive-gen2-nonprod -- clusters/non-prod-gen2 crds/non-prod-gen2 infra/non-prod-gen2 apps/non-prod-gen2`;
the VMs also need to be powered on (Terraform in `home-playbooks/terraform/chimaera`) and the cluster bootstrapped from `home-playbooks`.
