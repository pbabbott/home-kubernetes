# Dev Environment - Main

The purpose of this document is to explain how one can get started working on this project by configuring their dev environment.

- [Dev Environment - Main](#dev-environment---main)
  - [Procedure](#procedure)
    - [1. Open project with Remote SSH](#1-open-project-with-remote-ssh)
    - [2. Create an `.env` file](#2-create-an-env-file)
    - [3. Re-open the project in a devcontainer](#3-re-open-the-project-in-a-devcontainer)
    - [4. Ensure connectivity to 1Password](#4-ensure-connectivity-to-1password)
    - [5. Check your SSH key](#5-check-your-ssh-key)
    - [6. Get KubeConfig file](#6-get-kubeconfig-file)
    - [7. Enable the pre-commit hook](#7-enable-the-pre-commit-hook)
    - [8. Celebrate ✨](#8-celebrate-)


## Procedure

This project is meant to run in a devcontainer on a remote VM in my homelab.  Below there are a few commands so that one can spin up this project rapidly.

### 1. Open project with Remote SSH

First, make sure you've cloned this repository onto network-connected VM located with access to other nodes and clusters.

Then, open up the repository with VSCode using the `Remote - SSH` extension.

### 2. Create an `.env` file

Next, create an .env file for this devcontainer. 

```sh
cp ./.devcontainer/devcontainer.env ./.devcontainer/.env
```

> [!TIP]
> This is a great time to set various tokens and secrets in the `.env` file as it won't be committed to GH.

### 3. Re-open the project in a devcontainer

VS Code will detect that there is a devcontainer definition, and you can open up that project with that! Or if you miss the pop-up, you can always use the VScode command palette.

The `.env` file you setup in the previous step will set environment variables for your terminal.

### 4. Ensure connectivity to 1Password

Obtaining the various secrets in the next step will require access to 1Password.  Follow this guide to login to 1password, then report back here.

[Dev Guide - Login to 1Password](./login-to-one-password.md)


### 5. Check your SSH key

The devcontainer bind-mounts the host's `~/.ssh` (read-only), so the key you use on the VM is already available here. It must be authorized on the cluster nodes, because the kubeconfig in the next step is fetched over SSH.

### 6. Get KubeConfig file

First do an ssh login to the controller once manually to trust fingerprint.  There are shortcuts already setup:
```sh
# First, SSH to k8s controller from the devcontainer
$ controller 

# Type (y) when prompted

# In the controller vm, logout.
$ logout 
```

Now, back here in the devcontainer, get the kubeconfig file with the workspace script (run from the workspace root, outside this repo):
```sh
scripts/get-kubeconfig.sh prod-gen3
```

### 7. Enable the pre-commit hook

Run `pre-commit install` once per clone. It enforces that every file in `scripts/` has a row in `scripts/CLAUDE.md`.

### 8. Celebrate ✨

You can now interact with the cluster using tools like `kubectl` `kubeseal` `helm` `k9s` `kubectx` `kubens` `flux` and more!

You can also connect to any of the nodes with ssh to diagnose issues further!