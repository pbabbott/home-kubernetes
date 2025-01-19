# Dev Guide - Log into One Password

The purpose of this document is to explain how to log into 1Password, as there are a few scenarios to account for.

## Overview

This cluster is set up with 1Password connect server located at `op-connect.local.abbottland.io` - Read more about this integration here: [Reference - 1Password Integration Overview](./reference-1password-integration-overview.md).

In the case that the server is up or down, the steps might be slightly different.  That is, the server might be down if some sort of experiment is going on, or perhaps a brand-new cluster is being built on new infra.

### Connect server is available

When the connect server is available, communication with it is easy!

You just need to export the following variables in your shell:

```sh
# One Password Connect
OP_CONNECT_HOST="https://op-connect.local.abbottland.io"
OP_CONNECT_TOKEN="TOKEN_GOES_HERE"
```

The token can be obtained from the Homelab vault under `Production Access Token: Kubernetes`

### Connect server is not available

In the case that the connect server is down.  You'll want to instead use this command:

```sh
eval $(op signin)  
```

This command will export necessary values into your shell so that subsequent interactions with `op` will succeed. Though, it is less than ideal as it sets up this container as a new host in 1password.