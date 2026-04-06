# Dev Guide - Sync Dashy Config

Sync the live Dashy dashboard config into the Helm chart template.

## Overview

When the Dashy dashboard config changes (new services, layout tweaks, etc.), the Helm chart template at `applications/base/dashy/templates/configmap.yaml` needs to be updated.

`scripts/sync-dashy-config.py` automates this by fetching the live config from the cluster, stripping YAML noise, and replacing live URLs with Helm template variables.

## Procedure

### Step 1 - Run the sync script

```sh
python3 scripts/sync-dashy-config.py
```

The script will pause and print step-by-step instructions for exporting the config from the Dashy UI (Edit → Export Config → Download as File).  Save the downloaded file to `temp/dashboard-config.yaml`, then press any key.

It will then:
- Strip YAML anchors and the `filteredItems` block
- Replace live URLs with `{{ .Values.urls.KEY }}` using mappings from `applications/non-prod-gen2/dashy/helmrelease.yaml`
- Write the result to `applications/base/dashy/templates/configmap.yaml`

> [!NOTE]
> If any URLs in the config have no matching entry in the helmrelease, the script will print a warning and leave them as-is.  Add the new URL to both `helmrelease.yaml` files before committing.

### Step 2 - Review the diff

```sh
git diff applications/base/dashy/templates/configmap.yaml
```

Confirm the only changes are content updates, not structural regressions.

### Step 3 - Commit and push

```sh
git add applications/base/dashy/templates/configmap.yaml
git commit -m "chore(dashy): sync config from live dashboard"
git push
```

Flux will pick up the change and reconcile both clusters automatically.
