# Dev Guide - Flux Bootstrap

The purpose of this document is to explain how one can bootstrap a kubernetes cluster with flux.  

- [Dev Guide - Flux Bootstrap](#dev-guide---flux-bootstrap)
  - [Procedure](#procedure)
    - [Step 1 - Obtain GH Token](#step-1---obtain-gh-token)
    - [Step 2 - Ensure local env is good](#step-2---ensure-local-env-is-good)
    - [Step 3 - Rotate the deploy key](#step-3---rotate-the-deploy-key)
    - [Step 4 - Run the bootstrap command](#step-4---run-the-bootstrap-command)


## Procedure

This process really only needs to be done "once" to effectively install flux into the cluster, but on occasion the bootstrap command will need to be changed to add more features into flux.  This means that the process will need to be run occasionally  whenever a cluster re-build happens or when new features are added to the flux installation.

### Step 1 - Obtain GH Token

```sh
# Get the existing secret
k get secret -n flux-system flux-system -o yaml

# Decode it
echo -n "DECODED_PASSWORD_VALUE_GOES_HERE" | base64 --decode

# Export it for use in the next step
export GITHUB_TOKEN="DECODED_VALUE_GOES_HERE"
export GITHUB_USER="pbabbott"
```

### Step 2 - Ensure local env is good

https://fluxcd.io/flux/get-started/

```sh
# Make sure kubectl is working (both client-and-server version should match)
kubectl version

# Make sure flux is installed
which flux

# Make sure you have a GH token and user variable set
echo $GITHUB_TOKEN
echo $GITHUB_USER

# Run flux pre-checks
flux check --pre
```

### Step 3 - Rotate the deploy key 

>[!IMPORTANT]
> This step is only required if the cluster is already boostrapped.  That is, for a first-time flux install, no need to do this step!

Delete the key with:
```sh
kubectl -n flux-system delete secret flux-system
```

It will be re-created with the next `bootstrap` command.

### Step 4 - Run the bootstrap command

If the bootstrap command ever changes, please update it here:

```sh
flux bootstrap github \
  --components-extra=image-reflector-controller,image-automation-controller \
  --token-auth \
  --owner=$GITHUB_USER \
  --repository=home-kubernetes \
  --branch=main \
  --path=./clusters/homelab \
  --personal
```
