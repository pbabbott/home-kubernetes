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


kubectl get kustomization -n flux-system flux-system -o yaml
kubectl get gitrepository -n flux-system flux-system -o yaml
kubectl logs -n flux-system deploy/kustomize-controller -f