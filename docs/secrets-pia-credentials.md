# Secrets - Private Internet Access Credentials

The purpose of this document is to explain how one can rotate and manage the secrets for Private Internet Access.

## Overview

The Private Internet Access secret is in the `media` namespace and its called `pia-credentials`.  It needs to have two keys named `username` and `password`.

It's then used in `qbittorrent-deployment.yml` to ensure `gluetun` can connect to a VPN.

## Rotation instructions

Rotation for this secret is super easy since its in 1Password. All you have to do is update the secret in the 1Password UI!

Then the operator will monitor for change and update the k8s secret, which will then update the deployment.  The interval for 1password is set to 600 seconds which will take 10min for the rotation to take effect.