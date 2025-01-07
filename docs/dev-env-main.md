# Dev Environment - Main

The purpose of this document is to explain how one can get started working on this project by configuring their dev environment.

- [Dev Environment - Main](#dev-environment---main)
  - [Procedure](#procedure)
    - [1. Open project in a devcontainer](#1-open-project-in-a-devcontainer)
    - [2. Login to 1password](#2-login-to-1password)
    - [3. Get SSH Key](#3-get-ssh-key)
    - [4. Build .env file](#4-build-env-file)
    - [5. Get KubeConfig file](#5-get-kubeconfig-file)
    - [6. Celebrate ✨](#6-celebrate-)


## Procedure

This project is meant to run in a devcontainer on a remote VM in my homelab.  Below there are a few commands so that one can spin up this project rapidly.

### 1. Open project in a devcontainer

First, make sure you've cloned this repository onto network-connected VM located with access to other nodes and clusters.

Then, open up the repository with VSCode using the `Remote - SSH` extension.

After that, then VS Code will detect that there is a devcontainer definition, and you can open up that project with that!

### 2. Login to 1password

Obtaining the various secrets in the next step will require access to 1password.  Run this command and follow the prompts

```sh
# Requires secret key from 1Password
eval $(op signin)
```

### 3. Get SSH Key

This command helps get the SSH `id_rsa` public/private key pair to quickly connect to remote hosts.

```sh
./scripts/get-ssh-key.sh
```

> [!NOTE]
> This SSH key will enable password-less login to many of my VMs and cluster nodes, but is primarily used to get access to the kubeconfig file.  
> 
> TODO: This step should be replaced with getting the kubeconfig file from `1Password` instead.

### 4. Build .env file

This command will automatically build an .env file, pulling data from 1Password.

```sh
./scripts/build-env-file.sh
```

This `.env` file is used to run `kubeseal` so that in-cluster sealed-secrets may be created with local values.

### 5. Get KubeConfig file

First do an ssh login to the controller once manually to trust fingerprint.  There are shortcuts already setup:
```sh
# First, SSH to k8s controller from the devcontainer
$ controller 

# Type (y) when prompted

# In the controller vm, logout.
$ logout 
```

Now, back here in the devcontainer, Get the kubeconfig file
```sh
./scripts/get-kube-config-file.sh
```

### 6. Celebrate ✨

You can now interact with the cluster using tools like `kubectl` `kubeseal` `helm` `k9s` `kubectx` `kubens` `flux` and more!

You can also connect to any of the nodes with ssh to diagnose issues further!