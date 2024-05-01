# home-kubernetes
A gitops-based approach for all my kubernetes charts, manifests, and helm deployments. Flux for cluster-level, ArgoCD for applications


# Getting Started with Flux

## Install Flux

[Flux Documenation: Installation instructions](https://fluxcd.io/flux/installation/#install-the-flux-cli)

## Ensure local env is good

https://fluxcd.io/flux/get-started/

```sh
kubectl version
which flux
echo $GITHUB_TOKEN
echo $GITHUB_USER
flux check --pre
```

## Install flux onto cluster

```sh
flux bootstrap github \
  --token-auth \
  --owner=$GITHUB_USER \
  --repository=home-kubernetes \
  --branch=main \
  --path=./clusters/homelab \
  --network-policy=false \
  --personal
```

# Debugging Commands
kubectl get kustomization -n flux-system flux-system -o yaml
kubectl get gitrepository -n flux-system flux-system -o yaml
kubectl logs -n flux-system deploy/kustomize-controller -f

# Deploy Pod Info

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