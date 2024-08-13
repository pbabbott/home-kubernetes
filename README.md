# home-kubernetes
A gitops-based approach for all my kubernetes charts, manifests, and helm deployments. Flux for cluster-level, ArgoCD for applications

- [home-kubernetes](#home-kubernetes)
- [Get Started with this Project](#get-started-with-this-project)
  - [Getting Started Procedure](#getting-started-procedure)
    - [1. Login to 1password](#1-login-to-1password)
    - [2. Get SSH Key](#2-get-ssh-key)
    - [3. Build .env file](#3-build-env-file)
    - [4. Get KubeConfig file](#4-get-kubeconfig-file)
- [Resources](#resources)
  - [Chart documentation](#chart-documentation)
    - [Verdaccio](#verdaccio)
    - [ingress-nginx](#ingress-nginx)
    - [Prometheus](#prometheus)
    - [Harbor](#harbor)
  - [Helpful ingress command](#helpful-ingress-command)


# Get Started with this Project

This project is meant to run in a devcontainer.  There are a few commands set up to build your environment rapidly.

## Getting Started Procedure

### 1. Login to 1password
```sh
# Requires secret key from 1Password
eval $(op signin)
```

### 2. Get SSH Key

This command helps get the SSH id_rsa key to quickly connect to remote hosts.

```sh
./scripts/get-ssh-key.sh
```

### 3. Build .env file

This command will automatically build an .env file, pulling data from 1Password.

```sh
./scripts/build-env-file.sh
```

### 4. Get KubeConfig file

Login to the controller once manually to trust fingerprint
```sh
$ controller # SSH to k8s controller from the devcontainer
$ logout # In the controller vm, logout.
```

Back here in the devcontainer, Get the kubeconfig file
```sh
./scripts/get-kube-config-file.sh
```

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