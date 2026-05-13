# SSH Known Hosts Mismatch Incident

**Date:** 2026-05-02  
**Time:** ~00:34 UTC  
**Cluster:** non-prod-gen2  
**Severity:** Medium (Flux unable to pull from GitHub; no cluster workloads affected)

## Symptom

Flux `GitRepository/flux-system` entered a failed state and could not fetch new commits from GitHub:

```
failed to checkout and determine revision: unable to list remote for
'ssh://git@github.com/pbabbott/home-kubernetes': ssh: handshake failed:
knownhosts: key mismatch
```

All subsequent Kustomization and HelmRelease reconciliations were blocked on the stale artifact (`c637d0d`). New commits (including `9007f9e` enabling Longhorn ServiceMonitor) were not applied.

## Root Cause

The `known_hosts` field in the `flux-system/flux-system` Secret contained a stale GitHub SSH host key. GitHub periodically rotates SSH host keys; the stored value no longer matched.

## Remediation

Patched the `known_hosts` field in the `flux-system` Secret with fresh keys from `ssh-keyscan`, then triggered an immediate reconciliation:

```bash
kubectl patch secret flux-system -n flux-system \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/known_hosts\", \"value\": \"$(ssh-keyscan github.com 2>/dev/null | base64 -w0)\"}]" \
  && flux reconcile source git flux-system
```

## Prevention

If this recurs, check `kubectl get gitrepository -n flux-system` for `FetchFailed` with `knownhosts: key mismatch` and re-run the patch above.
