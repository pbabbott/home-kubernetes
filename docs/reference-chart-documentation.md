# Reference - Chart Documentation

The purpose of this document is to serve as a landing page full of links to easily find documentation for installations in my homelab.

This document does not have documentation on all installations or technologies, its mostly just the pages I frequently refer to.

## General Reference Materials

### Kustomization

- https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/

## Installations

### Verdaccio

- Install Instructions https://verdaccio.org/docs/kubernetes/#install
- Helm docs https://github.com/verdaccio/charts

### ingress-nginx

- `config:` documentation https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
- `helm chart docs:` https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx
- `custom headers:`
https://kubernetes.github.io/ingress-nginx/examples/customization/custom-headers/

```sh
helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx > temp/ingress-nginx.yaml
```

### Prometheus

- prometheus operator (custom CRDs spec): https://prometheus-operator.dev/docs/api-reference/api/

### Harbor

```sh
helm show values harbor/harbor > temp/harbor.yaml
```
