# Reference - 1Password - Integration Overview

The purpose of this document is to explain how 1Password is setup within this repository.

## Overview

I'm using two methods to manage secrets in this cluster, please see [Reference - Secret Management Strategy](./reference-secret-management-strategy.md) for more information.  This document is just focused on the 1Password integration.

I'm using a vault in my 1Password account to manage secrets for my homelab and for this flux project.  The way that 1Password works is that there's a HTTP REST API server that needs to be hosted in my infra called the [Connect Server](https://developer.1password.com/docs/connect/).  This server basically proxies requests to 1Password and can even be used in tandem with a 1password kubernetes operator.

## Offerings

This 1Password integration provides two major offerings to my homelab:
- `op-connect.local.abbottland.io`
  - This URL along with the `OP_CONNECT_TOKEN` can be used to fetch secrets. I intend to use this extensively within [pbabbott/home-web-apps](https://github.com/pbabbott/home-web-apps).
- 1Password operator.
  - This enables password and kubernetes secrets to be deployed as kubernetes code!
  - Check out the [Usage Examples Documentation](https://developer.1password.com/docs/k8s/k8s-operator#usage-examples) to see how this works.


## Integration Procedure

These are the steps I took to enable the integration.  Each cluster (homelab, non-prod gen2) needs its own SealedSecret because SealedSecret ciphertext is encrypted for a specific cluster's sealed-secrets controller and is not portable.  Repeat this procedure once per cluster, noting the cluster-specific differences in Steps 4 and 5.

### Step 1 - Follow steps on 1Password documentation site

Following their documentation, you'll need to follow "Step 1: Create a Secrets Automation workflow"

https://developer.1password.com/docs/connect/get-started

This will give you two things:

- A `1password-credentials.json` file. It contains the credentials necessary to deploy 1Password Connect Server.
- An access token: `OP_CONNECT_TOKEN`. This is used applications or services to authenticate with the Connect REST API. And it is used in the 1password kubernetes operator.

>[!TIP]
> Create a dedicated workflow per cluster to keep environments independent. The homelab credentials are stored in the `Homelab` vault as `Kubernetes Production Credentials File`; non-prod gen2 credentials are stored as `Kubernetes Non-Prod Gen2 Credentials File`.

### Step 2 - Obtain the file

Next, we need to put the `1password-credentials.json` into the root of this repository.  Don't worry, its been added to `.gitignore`

>[!TIP]
> Delete the file after you're done with it, as we don't want this sensitive data just hanging around. 

### Step 3 - Export the token

```sh
export OP_CONNECT_TOKEN="TOKEN VALUE GOES HERE"
```

### Step 4 - Create a SealedSecret

Make sure your `kubectl` context is pointed at the target cluster, then run the appropriate command:

**Homelab**
```sh
./scripts/op-connect-secret.sh
```

**Non-prod gen2**
```sh
OP_CONNECT_SEALED_SECRET_OUTPUT=./infra/non-prod-gen2/onepassword/op-credentials.yaml ./scripts/op-connect-secret.sh
```

This will create or overwrite the existing SealedSecret enabling the 1password integration.

### Step 5 - (Non-prod gen2 only) Wire up the kustomization

Add `op-credentials.yaml` to the resources list in `infra/non-prod-gen2/onepassword/kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - op-connect-helm-repo.yaml
  - op-connect-helm-release.yaml
  - op-credentials.yaml
```

### Step 6 - Commit

```sh
git add .
git commit -m "Update op-connect credentials file"
```

Push this stuff to remote and then flux will sync it to the cluster

### Step 7 - Delete the credentials file

```sh
rm 1password-credentials.json
```
