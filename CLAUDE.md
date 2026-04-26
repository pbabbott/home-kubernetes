
## Repository Folder Structure

This repository contains two sets of top-level directories, each tied to a different cluster generation:

### Gen 1 (homelab / "prod gen 1")
- `apps/` — application workloads deployed to the gen 1 cluster
- `infrastructure/` — infrastructure components (controllers, operators, etc.) for the gen 1 cluster

### Gen 2 (prod gen 2 & non-prod gen 2)
- `crds/` — CRD installs and CRD-layer Helm/releases per cluster path (e.g. `crds/non-prod-gen2/`)
- `applications/` — application workloads deployed to gen 2 clusters
- `infra/` — infrastructure components for gen 2 clusters (after CRDs are present)
