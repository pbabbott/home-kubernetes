# Secrets - Registry Credentials

The purpose of this document is to explain how registry credentials can be updated and rotated across the cluster.

## Overview

There is a container registry located at https://harbor.local.abbottland.io.  There are several services set up that require interaction with this private container registry:

- `gluetun-sync`
- `flux-system`

## Update Procedure

The username and password for the registry exist in 1Password and can be updated via the harbor UI.  Once the credentials have been updated, and extra step is required to update the various registry credentials across the cluster since the username/password pair needs to be transformed into a special secret format.

### Step 1 - Update Secret Value

Go to harbor website and update the secret value in the UI

### Step 2 - Update Sealed Secrets

Next, we need to run a script to take this username/password combo, transform them into a docker registry secret.  This script will then update various SealedSecrets throughout the cluster.

```sh
./scripts/update-regcred-secret.sh
```

### Step 3 - Commit and Push

Commit and push the changes to remote.
