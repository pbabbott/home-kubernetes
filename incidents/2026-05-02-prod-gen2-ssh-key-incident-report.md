# SSH Known Hosts Mismatch Incident — prod-gen2

**Date:** 2026-05-02  
**Time detected:** ~17:00 UTC  
**Time resolved:** ~18:05 UTC  
**Cluster:** prod-gen2  
**Severity:** Medium (Flux unable to pull from GitHub; existing cluster workloads unaffected)

## Symptom

Flux `GitRepository/flux-system` entered a failed state and could not fetch new commits from GitHub:

```
failed to checkout and determine revision: unable to list remote for
'ssh://git@github.com/pbabbott/home-kubernetes': ssh: handshake failed:
knownhosts: key mismatch
```

Last successful artifact fetch: `2026-05-02T15:24:02Z` (revision `d7be2ea`).  
Error first observed: `2026-05-02T17:00:34Z`.  
All subsequent reconciliations blocked on the stale artifact; no new commits applied during the window.

## Root Cause

The `known_hosts` field in the `flux-system/flux-system` Secret contained a value that no longer matched the key GitHub presented during SSH handshake. Source-controller had cached the stale value in memory; patching the secret alone was insufficient without a pod restart.

This is the same pattern as the non-prod-gen2 incident earlier the same day.

## Remediation

1. Patched `known_hosts` with fresh keys from `ssh-keyscan`:

```bash
kubectl patch secret flux-system -n flux-system \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/known_hosts\", \"value\": \"$(ssh-keyscan github.com 2>/dev/null | base64 -w0)\"}]"
```

2. Restarted source-controller to clear in-memory cache:

```bash
kubectl rollout restart deployment/source-controller -n flux-system
kubectl rollout status deployment/source-controller -n flux-system --timeout=60s
```

3. Triggered immediate reconciliation:

```bash
flux reconcile source git flux-system -n flux-system --timeout=60s
flux reconcile kustomization flux-system -n flux-system --timeout=60s
```

Cluster resumed syncing at revision `03c7bceda6db95eb6270adee274e0b812fb0a3f0`.

## Prevention

Same issue occurred on non-prod-gen2 earlier today — both clusters were affected. If this recurs:

1. `kubectl get gitrepository -n flux-system` — look for `FetchFailed` with `knownhosts: key mismatch`
2. Re-run steps 1–3 above on the affected cluster
3. Consider automating known_hosts rotation or adding a Prometheus alert on `gotk_reconcile_condition{type="Ready",status="False",kind="GitRepository"}`
