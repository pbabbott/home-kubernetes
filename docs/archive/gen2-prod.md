# Gen 2 prod: `prod-gen2`

Tag `archive-gen2-prod` -> commit `c32de0ea63f537c4fcaa0be758e28f31e2924691` (2026-11-08, last commit where prod-gen2 was complete).
Removed paths: `clusters/prod-gen2/`, `crds/prod-gen2/`, `infra/prod-gen2/`, `applications/prod-gen2/`.
Apps were pruned from gen2 as they moved to gen3 (2026-11-08 to 2026-11-09); at later commits the overlay is nearly empty.

## What it was
The production Kubernetes cluster from 2026-03 (first Flux commit 2026-03-22) to 2026-11-09: kubeadm-built VMs on the
`chimaera` Proxmox host (controller `tf-prod-k8s-controller-1` and workers `tf-prod-k8s-worker-1..3`), created with
Terraform + Ansible (`home-playbooks/playbooks/kubernetes-gen2/`). Retired in the gen3 migration: Flux Kustomizations
suspended and VMs 204-207 powered off on 2026-11-09 (rollback window to ~2026-12-07, then destroyed, issue #40).
Hosts: `home-playbooks/docs/HOSTS.md`. Migration story and per-app learnings: `docs/plans/2026-11-08-gen2-to-gen3-migration.md`.

## Flux layout
Flux Operator (`FluxInstance` in `clusters/prod-gen2/flux-system`, later `flux-gitops`) syncing four numbered
Kustomizations that each depended on the previous one: `00-crds-ks` (`crds/prod-gen2`), `01-infra-ks` (`infra/prod-gen2`),
`02-apps-ks` (`applications/prod-gen2`) and `03-flux-gitops-ks` (the FluxInstance itself). Overlays were thin: each
`applications/prod-gen2/<app>/kustomization.yaml` referenced `applications/base/<app>` and patched hostnames,
labels or sizing. Ingress: Istio ambient + Gateway API (`istio-ingress` internal, `istio-ingress-public` public) behind the HAProxy LXC `192.168.6.28`.
DNS: two external-dns instances (Cloudflare for `*.abbottland.io`, Pi-hole for `*.local.abbottland.io`).
Secrets: 1Password Connect operator (`OnePasswordItem`), with SealedSecrets only to bootstrap it.

## Infrastructure
| Component | Summary |
| --- | --- |
| crds | Everything with CRDs installed first from `crds/base/*`: Istio, Gateway API, cert-manager, flux-operator, sealed-secrets, onepassword, kube-prometheus-stack, external-dns, longhorn. |
| flux-operator | Flux Operator Helm release managing the Flux controllers through a `FluxInstance`. |
| sealed-secrets | Base sealed-secrets controller; used to bootstrap the 1Password Connect credentials. |
| onepassword | 1Password Connect + operator; `op-credentials` sealed per cluster. |
| cert-manager | Let's Encrypt (staging/prod ClusterIssuers, Cloudflare DNS-01) issuing the wildcard gateway certs. |
| istio | Istio ambient mesh (istiod, cni, ztunnel) plus the two Gateways and an IP allowlist policy. |
| longhorn | Replicated block storage; recurring backups to the NAS NFS target `longhorn-prod` (`longhorn-recurring-job.yaml` + HelmRelease patch). |
| nas-storage | NFS subdir provisioner StorageClass (`nas-storage`) on the Asustor NAS. |
| kube-prometheus-stack | Prometheus, Grafana and Alertmanager with gitops-managed dashboards. |
| external-dns | Cloudflare and Pi-hole external-dns instances reading HTTPRoutes by label. |
| pihole | Proxy route to the Pi-hole admin UI on `bananapi` (moved to the infra layer 2026-05-22). |
| metrics-server, priorityclass | Shared base: resource metrics API and cluster PriorityClasses. |

## Applications (19 at the peak)
| App | Summary |
| --- | --- |
| arc | Actions Runner Controller scale sets (`prod-gen2-amd64-runner`, `prod-gen2-dind-runner`) for home-web-apps CI, plus actions-cache and turborepo remote cache servers. |
| asustor | Service + EndpointSlice + routes proxying the NAS admin UI. |
| blog | Public blog (apex `abbottland.io`), image automation, NetworkPolicy. |
| coder | Coder dev-workspace platform (Helm) with NAS Postgres and a workspaces namespace. |
| dashy | Dashy dashboard as a local Helm chart with per-cluster values. |
| diagram-maker | Public diagram-maker app with NetworkPolicy and image automation. |
| fui-components | Public component-library site with NetworkPolicy and image automation. |
| haproxy | Proxy to the HAProxy stats page plus a Prometheus scrape config. |
| harbor | Harbor registry (Helm) with NAS-backed registry storage; Docker Hub proxy mirror for CI. |
| harbor-cleanup | Custom service (own image, ClusterRole, ConfigMap, routes) that cleans up Harbor; see `docs/plans/2026-06-01-harbor-cleanup.md`. |
| home-assistant | Public route (via Cloudflare) to the Home Assistant host. |
| home-hud | home-hud dashboard with video-api/-worker, backup worker, and `homelab-api`, all with image automation and ServiceMonitors. |
| mcp-grafana | Grafana MCP server exposed internally for AI agents. |
| media | sonarr, radarr, prowlarr, qBittorrent and gluetun (VPN), with config PVCs on Longhorn and media on NFS. |
| openclaw | OpenClaw agent platform (replaced n8n, 2026-10) with config map, PVC and NetworkPolicy. |
| plex | Service + EndpointSlice proxying Plex on the NAS. |
| podinfo | Test app used to prove public/internal routing and certs. |
| proxmox | Proxy route to the Proxmox UI with an Istio DestinationRule. |
| umami | Self-hosted analytics (public script, internal admin) on NAS Postgres. |

## Why it was retired
Replaced by gen3 (k3s on `hogwarts`, the new primary Proxmox host; `chimaera` was maxed out). Gen3 reuses `applications/base`, `infra/base`
and the same layering with `prod-gen3` overlays.

## Restoring it
`git checkout archive-gen2-prod -- clusters/prod-gen2 crds/prod-gen2 infra/prod-gen2 applications/prod-gen2` (then check
`applications/base` for gen3-era changes; the tag's `base` is the one these overlays were written against). The VMs would also need
to be powered on and Flux unsuspended; see the migration plan's rollback notes.
