# Getting Started with Flux

This project is set up with flux.  Here are some helpful commands.

- [Getting Started with Flux](#getting-started-with-flux)
  - [Debugging Commands](#debugging-commands)
  - [Manual Flux Manifest Creation](#manual-flux-manifest-creation)
  - [helpful sync commands](#helpful-sync-commands)


## Debugging Commands

```sh
kubectl get kustomization -n flux-system flux-system -o yaml
kubectl get gitrepository -n flux-system flux-system -o yaml
kubectl logs -n flux-system deploy/kustomize-controller -f
```

## Manual Flux Manifest Creation

These steps show how you can generate manifest files with `flux create`

```sh
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=1m \
  --export > ./clusters/homelab/podinfo-source.yaml
```

```sh
  flux create kustomization podinfo \
  --target-namespace=default \
  --source=podinfo \
  --path="./kustomize" \
  --prune=true \
  --wait=true \
  --interval=30m \
  --retry-interval=2m \
  --health-check-timeout=3m \
  --export > ./clusters/homelab/podinfo-kustomization.yaml
```

## helpful sync commands

```sh
k get gitrepository -A
flux -n flux-system reconcile source git flux-system

flux -n flux-system reconcile kustomization flux-system

k get kustomization -A
flux -n flux-system reconcile kustomization infra-controllers
```