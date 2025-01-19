# Reference - Secret Management Strategy

The purpose of this document is to explain how SealedSecrets are used within this repository.

## Strategic Overview

This repository has been set up with 2 different methods to manage secrets: Sealed Secrets and 1Password.

Sealed Secrets are great because they can be created in an encrypted manner and pushed to a git repository. See [Flux's documentation on Sealed Secrets](https://fluxcd.io/flux/guides/sealed-secrets/) or the [Bitnami Labs Documentation](https://github.com/bitnami-labs/sealed-secrets) for more information.  I would like this flux repository to be easily reproduced in the event i need to rebuild my kubernetes nodes.  Having Sealed Secrets helps make this possible as they can be committed to the repository. Even if they need to be rotated upon rebuilding the cluster, its a great way to maintain this idea of infrastructure as code.

1Password has also been configured to connect with my Homelab vault.  This is nice as I can rotate secrets and they'll automatically update here in my cluster.  There is also a lot less overhead in working with 1Password secrets as there's a nice UI and apps across all my devices where secrets can be managed.  These secrets are great for use with various services like databases, websites, api keys, etc.. which need to be rotated on occasion. The 1password integration itself also depends on Sealed Secrets for its initial setup and connectivity to the vault.  Here is where you can read more about the [1password Integration Overview](./reference-1password-integration-overview.md) for how this works.

## When to use which?

### 1Password
- Requires an initial step for integration (Sealed Secrets enables this)
- Secrets can be deployed as code along side applications, services and various controllers
- UI allows for easy management and rotations
- The default choice for secrets. consider this as option "A"
  - That is, try to use 1Password secrets for everything
  - Use a different option if it would make the cluster not easily re-built.

### Sealed Secrets
- Overhead is fairly high, as secrets need to be created and updated via shell script
- Can be great to ensure cluster can be reproduced in an event of a total rebuild
- Used to enable 1Password connectivity
- Can be great when additional transformations are needed
  - for example, registry credentials need to be in a dockerconfig json format, and i would like to manage the username and password in 1password, and i don't really want duplication here.
- The backup choice for secrets. Consider this as option "B"
  - That is, only use SealedSecrets when you have to.