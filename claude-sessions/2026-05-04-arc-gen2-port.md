# ARC Port to Non-Prod Gen2

**Date:** 2026-05-04  
**Commit:** 612e455

## What we did

Ported GitHub Actions Runner Controller (ARC) from gen1 (`apps/homelab/arc/`) to non-prod gen2, switching from the legacy `actions-runner-controller` chart (0.23.7, maintenance-mode) to the officially recommended `gha-runner-scale-set` 0.14.1.

## Key decisions

- **Chart**: `gha-runner-scale-set` 0.14.1 via OCI (`oci://ghcr.io/actions/actions-runner-controller-charts`)
- **Architecture**: `AutoscalingRunnerSet` + listener pod per scale set (replaces `RunnerDeployment` + `HorizontalRunnerAutoscaler`)
- **Namespaces**: `arc-systems` (controller) + `arc-runners` (scale sets + runner pods) — matches upstream convention
- **Runners**: Two amd64 scale sets only (dropped arm64 — no arm64 nodes in gen2)
  - `gen2-amd64-runner` — standard runner, min 1 / max 2
  - `gen2-dind-runner` — dind mode, min 1 / max 2
- **Labels**: Distinct `gen2-*` prefix so gen1 and gen2 coexist without job collisions during bake period
- **Auth**: 1Password `OnePasswordItem` → `arc-gh-secret` in `arc-runners` ns; item must have field `github_token`
- **Layout**: base/overlay pattern (`applications/base/arc/` + `applications/non-prod-gen2/arc/`)

## Files created

```
applications/base/arc/
  arc-systems-ns.yaml
  arc-runners-ns.yaml
  gha-runner-scale-set-charts-helmrepository.yaml
  arc-controller-helmrelease.yaml
  arc-runner-amd64-helmrelease.yaml
  arc-runner-dind-amd64-helmrelease.yaml
  kustomization.yaml

applications/non-prod-gen2/arc/
  arc-gh-secret.yaml
  arc-controller-servicemonitor.yaml
  kustomization.yaml
```

## Files modified

- `applications/non-prod-gen2/kustomization.yaml` — added `- ./arc`

## Pending before apply

- Verify 1Password item `vaults/Homelab/items/arc-gh-secret` has a field named `github_token` (rename if field has different name — listener pod CrashLoops otherwise)
- Update workflows in `pbabbott/home-web-apps` to target `gen2-amd64-runner` / `gen2-dind-runner` labels to route jobs to gen2

## Verification commands

```bash
flux reconcile source git flux-system
flux reconcile kustomization apps-ks --with-source
flux get helmrelease -A | grep arc
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
kubectl get autoscalingrunnerset -A
kubectl get ephemeralrunner -n arc-runners -w
```
