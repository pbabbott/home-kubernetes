# Secrets - QBitTorrent Credentials

The purpose of this document is to explain how the QbitTorrent Credentials are set up and how they're rotated.

## Overview

The QbitTorrent secret is in the `media` namespace and its called `qbittorrent-credentials`. It needs to have one key named `password`.

It's then used in `qbittorrent-deployment.yml` to ensure `gluetun-sync` can make changes to the QbitTorrent service (namely the port).

## Rotation Instructions

Rotation for this secret is super easy since its in 1Password. All you have to do is update the secret in the 1Password UI!

Then the operator will monitor for change and update the k8s secret, which will then update the deployment.  The interval for 1password is set to 600 seconds which will take 10min for the rotation to take effect.