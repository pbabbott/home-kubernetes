---
name: helm-values
description: Fetch real Helm chart default values from remote and cache to /tmp for reference — avoids guessing when writing HelmRelease values blocks
---

Use when about to write or modify `values:` in a HelmRelease, or when the user asks what values a chart supports.

## Goal

Fetch `helm show values` for the chart, write to `/tmp/helm-values-<chart>.yaml`, then use that file as ground truth for all values decisions in this session.

## Steps

### 1. Identify the chart

From user args or conversation context, determine which HelmRelease to inspect. If a file path is given, read it. If only an app name is given, look for it at `applications/base/<name>/<name>-helmrelease.yaml`.

Extract from the HelmRelease:
- `spec.chart.spec.chart` → chart name
- `spec.chart.spec.version` → version constraint (e.g. `>=1.24.15`)
- `spec.chart.spec.sourceRef.name` → HelmRepository name

### 2. Find the repo URL

Run:
```bash
kubectl get helmrepository -n flux-system <sourceRef-name> -o jsonpath='{.spec.url}'
```

If kubectl fails, grep the repo files:
```bash
grep -r "name: <sourceRef-name>" applications/ infra/ --include="*.yaml" -l
```
then read the matching HelmRepository file for `spec.url`.

### 3. Add repo and fetch values

```bash
helm repo add __tmp_<chart> <url> 2>/dev/null || true
helm repo update __tmp_<chart> 2>/dev/null || true
helm show values __tmp_<chart>/<chart> > /tmp/helm-values-<chart>.yaml
```

If a specific version is needed (not a range), add `--version <version>`.

For semver ranges like `>=1.24.15`, omit `--version` to get latest, which is fine for reference.

### 4. Report and reference

Read `/tmp/helm-values-<chart>.yaml` and confirm it loaded. Tell the user:
> "Fetched chart values → `/tmp/helm-values-<chart>.yaml` (<N> lines). Using as reference."

Then use that file as the authoritative reference for all `values:` decisions — key names, nesting structure, default values, and available options.

## When multiple HelmReleases are in scope

Run steps 1-3 for each chart, saving separate files per chart name. Reference all of them.

## Notes

- `helm show values` returns chart defaults — not what's currently deployed. For deployed overrides use `helm get values <release> -n <namespace>`.
- Temp files persist for the session. On re-invoke for same chart, overwrite to pick up any version changes.
- If `helm` is not in PATH, report clearly rather than guessing.
