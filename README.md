# home-kubernetes
A gitops-based approach for all my kubernetes charts, manifests, and helm deployments. Flux for Gitops, 1password for secrets, and a variety of shell scripts to support a myriad of operators and applications.

- [home-kubernetes](#home-kubernetes)
- [Contribution](#contribution)
  - [Getting Started](#getting-started)
  - [Developer Guides](#developer-guides)
  - [Secret Rotations](#secret-rotations)
  - [Reference](#reference)

# Contribution 

This project is meant to run in a `devcontainer` on a VM in my homelab. That is, this codebase targets many specific aspects of my home infra and its not really meant to run anywhere else, though many of its parts could be made to be re-usable or serve as inspiration for others.

## Getting Started


Follow this guide to make sure you're ready to start work on this project: [Dev Environment - Main](./docs/dev-env-main.md)

## Developer Guides

These are common activities one might take while working on this repository.

- [Bootstrap the cluster with Flux](./docs/dev-guide-flux-bootstrap.md) - This is a one-time activity unless the cluster needs to be rebuilt or more flux features need to be added.
- [Login to 1Password](./docs/dev-guide-login-to-one-password.md) - Depending on the state of the connect server, here are some tips for authenticating with 1Password.
- [SealedSecrets - Create Manifest](./docs/dev-guide-sealed-secrets-create-manifest.md) - Here is how you can create a SealedSecret for use within the cluster
- [SealedSecrets - Update Values](./docs/dev-guide-sealed-secrets-update-values.md) - This is how you can update SealedSecret manifests with the help of some scripts.

## Secret Rotations

Secrets should be rotated and it can become a bit tedious to do so. These documents make it easier to discern each secret's usage and how it should be rotated.

- [Private Internet Access Credentials](./docs/secrets-pia-credentials.md)
- [QbitTorrent Credentials](./docs/secrets-qbittorrent.md)


## Reference
- [1Password Integration Overview](./docs/reference-1password-integration-overview.md) - Here is how 1Password is setup and steps to get it working in the case of cluster rebuild.
- [Chart Documentation](./docs/reference-chart-documentation.md) - A bunch of links to handy documentation websites and a few commands.
- [Secret Management Strategy](./docs/reference-secret-management-strategy.md) - Here is how to choose when to use 1Password or SealedSecrets.
