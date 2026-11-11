# Secrets - Registry Credentials

How the container registry credentials (Harbor, https://harbor.local.abbottland.io) are delivered to the cluster and rotated.

## Overview

Workloads that pull from or push to the private registry get a `kubernetes.io/dockerconfigjson` Secret named `regcred`
(and `regcred-flux` in `flux-system`, used by Flux image automation). They are all `OnePasswordItem` resources pointing at the
same 1Password item, so there are no sealed secrets to regenerate:

- `apps/base/ci-registry/regcred-flux/regcred-flux-onepassworditem.yaml` (Flux)
- `apps/base/<category>/<app>/regcred-onepassworditem.yaml` (blog, diagram-maker, fui-components, harbor-cleanup, home-hud, media)

Item: `vaults/Homelab/items/harbor.local.abbottland.io - admin`.

## Rotate

1. Change the credentials in the Harbor UI and in the 1Password item.
2. The 1Password operator picks up the change and updates every `regcred` Secret; `operator.1password.io/auto-restart` restarts the pods.
   To force it, see `docs/ai-reference-onepassword-operator.md`.

## Add `regcred` to a new app

Copy `apps/base/media/media/regcred-onepassworditem.yaml` into the app, change `namespace`, and list it in the app's `kustomization.yaml`.

The earlier sealed-secret approach (a script that regenerated `harbor-regcred.yaml` files) belonged to gen1 and is archived, see `docs/archive/gen1-homelab.md`.
