# Flux Operator rollout (non-prod-gen2)

This cluster drops `gotk-components.yaml` in favor of **FluxInstance** managed by **flux-operator**.

If you see Flux controller downtime on the first reconcile, use either:

1. **Two-step git push**: merge the branch that installs `flux-operator` + adds `FluxInstance` while **keeping** `gotk-components.yaml`, verify `kubectl -n flux-system get fluxinstance flux`, then remove `gotk-components.yaml` in a follow-up commit; or  
2. **Pre-apply**: from a machine with cluster access, `kubectl apply -f applications/non-prod-gen2/flux-gitops/fluxinstance.yaml` once the operator CRD exists, then push the commit that removes bootstrap manifests.

See [Flux Operator migration](https://fluxoperator.dev/docs/guides/migration/).
