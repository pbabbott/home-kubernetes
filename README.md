# home-kubernetes
A gitops-based approach for all my kubernetes charts, manifests, and helm deployments. Flux for cluster-level, ArgoCD for applications

- [home-kubernetes](#home-kubernetes)
- [Contribution](#contribution)
  - [Getting Started](#getting-started)
  - [Developer Guides](#developer-guides)
- [Resources](#resources)
  - [Chart documentation](#chart-documentation)
    - [Verdaccio](#verdaccio)
    - [ingress-nginx](#ingress-nginx)
    - [Prometheus](#prometheus)
    - [Harbor](#harbor)
  - [Helpful ingress command](#helpful-ingress-command)


# Contribution 

## Getting Started

This project is meant to run in a devcontainer on a VM in my homelab.

Follow this guide to make sure you're ready to start work on this project: [Dev Environment - Main](./docs/dev-env-main.md)

## Developer Guides

- [1Password - Enable the Integration](./docs/dev-guide-1password-connect-server.md) - The 1Password Connect Server allows access to all other secrets, here's how to get it working well.
- [Bootstrap the cluster with Flux](./docs/dev-guide-flux-bootstrap.md) - This is a one-time activity unless the cluster needs to be rebuilt or more flux features need to be added.
- [SealedSecrets - Create Manifest](./docs/dev-guide-sealed-secrets-create-manifest.md) - Here is how you can create a SealedSecret for use within the cluster
- [SealedSecrets - Update Values](./docs/dev-guide-sealed-secrets-update-values.md) - This is how you can update SealedSecret manifests with the help of some scripts.

# Resources

kustomization docs
https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/

## Chart documentation

### Verdaccio
https://verdaccio.org/docs/kubernetes/#install
https://github.com/verdaccio/charts

### ingress-nginx

`config:` documentation https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/

`helm chart docs:` https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx

`custom headers:`
https://kubernetes.github.io/ingress-nginx/examples/customization/custom-headers/

### Prometheus

prometheus operator (custom CRDs spec): https://prometheus-operator.dev/docs/api-reference/api/

### Harbor

```sh
helm show values harbor/harbor > harbor.yaml
```

## Helpful ingress command

```sh
helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx > temp.yaml
```