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
  --personal
```

# Debugging Commands

```sh
kubectl get kustomization -n flux-system flux-system -o yaml
kubectl get gitrepository -n flux-system flux-system -o yaml
kubectl logs -n flux-system deploy/kustomize-controller -f
```

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

# helpful sync commands

```sh
k get gitrepository -A
flux -n flux-system reconcile source git flux-system

flux -n flux-system reconcile kustomization flux-system

k get kustomization -A
flux -n flux-system reconcile kustomization infra-controllers

```
# Helpful ingress command

```sh
helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx > temp.yaml
```

# Resources

kustomization docs
https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/

# Chart documentation

## Verdaccio
https://verdaccio.org/docs/kubernetes/#install
https://github.com/verdaccio/charts

## ingress-nginx

`config:` documentation https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/

`helm chart docs:` https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx

`custom headers:`
https://kubernetes.github.io/ingress-nginx/examples/customization/custom-headers/

## Prometheus

prometheus operator (custom CRDs spec): https://prometheus-operator.dev/docs/api-reference/api/
