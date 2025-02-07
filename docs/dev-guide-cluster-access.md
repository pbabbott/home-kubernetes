# Dev Guide - Cluster Access

The purpose of this document is to explain how you can obtain kubeconfig file to access the cluster and then set it in 1Password for use by home-web-apps.

## Procedure

This process is meant to be done once the cluster is provisioned and then a kubeconfig file has been set up.  With a kubeconfig file available, it can be put into one password where it will then be accessed by applications that need it for deployment. 

### Step 1 - Obtain kubeconfig file.

As a part of setting up the dev environment, you should have ran `./scripts/get-kube-config-file.sh`.  This means that you should be able to run kubectl and interact with the cluster and a file should exist at `~/.kube/config` granting access to the cluster.

Please see [Dev Environment - Main](./dev-env-main.md) for details.

### Step 2 - Copy the file contents

Next up, we need to copy the file contents to the clipboard.

```sh
cat ~/.kube/config
```

Copy the contents to your clipboard

### Step 3 - Write to a file

On your host machine, open vs code, paste the contents into a new file called `config`

Write the file to your desktop

### Step 4 - Use the 1Password UI 

Next up, we need to open the 1Password UI to set this secret

Find the secret in the `Homelab` vault called `Kubeconfig Admin`

This secret is of type `document` and it expects to have one file called `config` 

Replace the file.

### Step 5 - Celebrate

Now `home-web-apps` can access the cluster! Wahoo!