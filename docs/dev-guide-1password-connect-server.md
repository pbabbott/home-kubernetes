# Dev Guide - 1Password - Connect Server 

The purpose of this document is to explain how one can make sure the 1Password Connect Server is working well with this repository. 

## Overview

I'm using a vault in my 1Password account to manage secrets for my homelab and for this flux project.  The way that 1Password works is that there's a HTTP REST API server that needs to be hosted in my infra called the [Connect Server](https://developer.1password.com/docs/connect/).  This server basically proxies requests to 1Password and can even be used in tandem with some cool kubernetes operators.  This guide is solely focused on making sure the Connect Server is operational as its used for everything else.

## Procedure

### Step 1 - Follow steps on 1Password documentation site

Following their documentation, you'll need to follow "Step 1: Create a Secrets Automation workflow"

https://developer.1password.com/docs/connect/get-started

This will give you two things:

- A `1password-credentials.json` file. It contains the credentials necessary to deploy 1Password Connect Server.
- An access token. Use this in your applications or services to authenticate with the Connect REST API. You can issue additional tokens later.

### Step 2 - Obtain the file

Next, we need to put the `1password-credentials.json` into the root of this repository.  Don't worry, its been added to `.gitignore`

The value in my vault is called `Kubernetes Production Credentials File` and its just in the `Homelab` vault.

>[!TIP]
> Delete the file after you're done with it, as we don't want this sensitive data just hanging around. 

### Step 3 - Create a SealedSecret

To create the SealedSecret, you just need to run this command:

```sh
./scripts/op-connect-secret.sh
```

This will just overwrite the existing SealedSecret.

### Step 4 - Commit

```sh
git add .
git commit -m "Update op-connect credentials file"
```

Push this stuff to remote and then flux will sync it to the cluster

### Step 5 - Delete the credentials file

```sh
rm 1password-credentials.json
```