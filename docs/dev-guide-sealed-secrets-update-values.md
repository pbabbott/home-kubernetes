# Dev Guide - SealedSecrets - Update Values

The purpose of this document is to explain how one can update sealed secrets within this repository.

## Overview

`SealedSecrets` is available for use within the cluster.  To setup a SealedSecret manifest, you can follow the [Dev Guide - SealedSecrets - Create Manifest](./dev-guide-sealed-secrets-create-manifest.md).

However if the cluster ever needs to be rebuilt, then all of the secret values need to be rebuilt as well!  Moreover, sometimes SealedSecret manifests need to be updated. 

In an effort to create a repeatable means to setup this cluster, i have created a way to quickly update values across all the sealed secrets.

## Procedure

> [!WARNING]
> While the following steps will still work, this process is basically deprecated.  That is, I would like to move to 1Password to manage secrets for my cluster.  I will work to use `SealedSecrets` just for the initial 1Password integration.  That way there will be less overhead in managing this stuff.

### Step 1 - Log into 1Password

The first step is to log into 1password using the CLI.  

```sh
eval $(op signin) 
```

> [!NOTE]
> This process is less than ideal as since this project is meant to run a devcontainer a new device needs to be setup every time the dev container is rebuilt!

### Step 2 - Build the .env file

Next up, we are going to fetch a bunch of values from 1Password and put everything into a `.env` file

This can be accomplished via:

```sh
./scripts/build-env-file.sh
```

This command will copy the `.env.sample` file to `.env`
Then it will fill in each key one at a time using values from 1Password.  Neat!

### Step 3 - Update SealedSecrets

Next, we need to make some changes to the file at `./scripts/update_kubeseal_secrets.sh`.  The idea is that this file will use the values from `.env` then it will target specific manifests in this repository and update the value with a new Sealed value.  At the bottom of this script, un-comment areas of this repository that need updating.

> [!NOTE]
> These items are commented out, as updating one secret can be annoying to recreate all the manifests.

This oddity is why I'm looking to replace this whole secret management process with something more flexible like 1Password.