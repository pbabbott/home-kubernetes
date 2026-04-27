
## Repository Folder Structure

This repository contains two sets of top-level directories, each tied to a different cluster generation:

### Gen 1 (homelab / "prod gen 1")
- `apps/` — application workloads deployed to the gen 1 cluster
- `infrastructure/` — infrastructure components (controllers, operators, etc.) for the gen 1 cluster

### Gen 2 (prod gen 2 & non-prod gen 2)
- `crds/` — CRD installs and CRD-layer Helm/releases per cluster path (e.g. `crds/non-prod-gen2/`)
- `applications/` — application workloads deployed to gen 2 clusters
- `infra/` — infrastructure components for gen 2 clusters (after CRDs are present)

## Working with the clusters

### Working with Flux

Instead of annotating resources, prefer to use `flux` on the command line - there is an mcp available for flux as well.

### Working with kubernetes

When issuing kubectl commands, you can simply using `kubectl` - there is no need for `ssh`

Additionally, `kubectx` is available to rapidly switch contexts.

## Reference

- `.cursor/infra.md` - For more complete information on infra, repository topology and common ssh targets
- `docs/` common operational processes usually carried out to maintain the cluster, rotating secrets, etc.. 
- `.cursor/k8s-namespaces.md` A nice one-sentence summary of each namespace in the Kubernetes cluster. 
- `.cursor/k8s-namespaces.md` Explanation of how storage classes are set up in my kubernetes clusters. 
