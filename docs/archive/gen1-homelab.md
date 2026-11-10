# Gen 1: `homelab`

Tag `archive-gen1-homelab` -> commit `c32de0ea63f537c4fcaa0be758e28f31e2924691`.
Removed paths: `clusters/homelab/`, `apps/{homelab,media,public}/`, `infrastructure/{base,controllers,config}/`.

## What it was
The first Kubernetes cluster, built with kubeadm by the old `playbooks/kubernetes/` Ansible playbooks (one controller, three workers, plus `dumbledore`, a Raspberry Pi 4
used as an ARM node), managed by Flux from the `clusters/homelab` path (first Flux commit 2024-04-28, Flux v2.2.3
via `flux bootstrap` component manifests). Ingress was ingress-nginx with `Ingress` objects (no Gateway API / Istio).
Dead by the time gen3 was built; gen2's first Flux commit is 2026-03-22. Only its code remained. Hosts: `home-playbooks/docs/HOSTS.md`
(gen1 VMs and the `playbooks/kubernetes/` playbooks were removed from home-playbooks at its tag `pre-reorg-2026-11`).

## Flux layout
Six Kustomizations in `clusters/homelab/` with dependency order:
`infra-base` -> `infra-controllers` -> `infra-config`, then the three app sets `apps` (`apps/homelab`),
`public-apps` (`apps/public`) and `media` (`apps/media`) which depend on infra. `image-update-automation.yaml`
did image automation (ImageRepository + ImagePolicy + `$imagepolicy` markers). `harbor-regcred.yaml` held the
registry pull secret. Secrets were a mix of SealedSecrets and 1Password Connect.

## Infrastructure
| Component | Summary |
| --- | --- |
| cert-manager | Helm release; `letsencrypt-staging`/`letsencrypt-prod` ClusterIssuers using DNS-01 through Cloudflare. |
| ingress-nginx | Helm release with a ServiceMonitor; all apps exposed via `ingressClassName: nginx`, internal apps restricted with a `whitelist-source-range` annotation. |
| external-dns | Helm release writing Cloudflare DNS records from Ingresses. |
| cloudflare-ddns | Small Deployment (`oznu/cloudflare-ddns`) keeping the public apex A record on the home IP. |
| 1Password Connect | Helm `connect` chart (`op-credentials` sealed) giving the cluster access to the Homelab vault. |
| sealed-secrets | Bitnami Sealed Secrets controller for secrets committed to git. |
| Longhorn | Helm release for replicated block storage; `backupTarget` `nfs://<NAS>:/volume1/Backups/longhorn` (with a `cifs-secret`) and a daily recurring backup job at 02:00. |
| nas-storage | `nfs-subdir-external-provisioner` Helm release giving an NFS StorageClass on the NAS. |
| monitoring | kube-prometheus-stack, Loki and an OpenTelemetry collector (Helm). |
| grafana | grafana-operator with a staging and a prod Grafana instance, a Prometheus datasource and a hosts dashboard. |
| CoreDNS patch | `patch-core-dns-configmap.yaml` replaced the CoreDNS Corefile so cluster DNS forwards to Pi-hole (`192.168.4.144`). |

## Applications
| App | Summary |
| --- | --- |
| arc | Legacy summerwind actions-runner-controller (RunnerDeployment + HorizontalRunnerAutoscaler) with amd64, arm64 and dind runners for home-web-apps CI, plus a metrics ServiceMonitor. |
| dashy | Dashy dashboard from plain manifests with a `conf.yml` ConfigMap and a static icons PVC. |
| development | `brandon-dev` namespace and registry pull secret for ad-hoc development workloads. |
| harbor | Harbor registry Helm release, with admin/DB secrets from 1Password. |
| home-hud | `pi-led-api` (drives the Pironman LED/LCD on the Pi) with Harbor image automation and an Ingress. |
| verdaccio | Private npm registry Helm release with an Ingress. |
| media | sonarr, radarr, prowlarr, qBittorrent behind a gluetun VPN pod, plus `gluetun-sync` (keeps the forwarded port in qBittorrent); NFS `media-pv`, Longhorn config PVCs. |
| fui-components | Public in-house app: Deployment, NetworkPolicy, Harbor image automation, Ingress. |
| home-assistant | Service + Endpoints + Ingress proxying the Home Assistant host (not run in-cluster). |
| plex | Service + EndpointSlice + Ingress proxying Plex on the NAS (`plex.abbottland.io`). |

## Technology choices worth remembering
- Plain Kustomize plus Helm releases; no overlays per cluster (single cluster).
- Image automation in-cluster, writing tags back to git.
- NGINX Ingress + cert-manager DNS-01 wildcard certs; Cloudflare for public DNS.
- Replaced by gen2 (Istio ambient + Gateway API, `crds`/`infra`/`applications` layering with per-cluster overlays, Flux Operator). The reason is not recorded in this repo.
