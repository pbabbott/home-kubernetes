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

## Create Procedure

In order to set up a new instance of `regcred` in the cluster, there are a few steps that need to be followed:

### Step 1 - Create a new file

The first step is to create a new file where the secret should live. For example..

```sh
touch ./apps/homelab/development/harbor-regcred.yaml
```

### Step 2 - Update the update script

Next, we want to update the script called `update-regcred-secret.sh` that way we'll get updates whenever the update procedure is run

```sh
create_reg_cred_secret brandon-dev ./apps/homelab/development/harbor-regcred.yaml
```

### Step 3 - Run the update script

Finally, it makes sense to run the update script so that the newly created file gets actual content

### Step 4 - Commit, Push, Reconcile

The last step is to commit the sealed secret to git, push it to remote, and reconile changes into the cluster
