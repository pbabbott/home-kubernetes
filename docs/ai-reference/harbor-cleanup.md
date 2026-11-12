# harbor-cleanup: operating it safely

Deletes old tags from Harbor `library/<repo>`. Deletions are irreversible (recovery = rebuild the image in CI). App code: `home-web-apps/apps/harbor-cleanup/src/services/cleanupService.ts`. Manifests: `apps/base/ci-registry/harbor-cleanup/`. History: `docs/plans/2026-06-01-harbor-cleanup.md`.

## The one rule: a restart is a cleanup run

The pod runs a cleanup ~10s after **every start** (plus the `0 3 * * *` cron). Anything that restarts it can delete:

- `envFrom` means a ConfigMap-only change does **not** restart the pod, and the pod keeps the old config until it does restart.
- A Deployment template change does restart it. Flux dropping a leftover `kubectl rollout restart` annotation (`restartedAt`) is enough (this caused 17 unplanned deletions after #81).
- So to change repos or behaviour: set `CLEANUP_DRY_RUN: "true"` **in the same apply**, make sure the pod restarts, confirm the log shows `DRY RUN: no tags will be deleted` before anything else, review the `would delete` lines, then set it back to `"false"`.
- Emergency stop: `flux suspend kustomization apps-ks`, then `kubectl -n harbor-cleanup scale deploy/harbor-cleanup --replicas=0`.

## Config (`harbor-cleanup-configmap.yaml`)

- `CLEANUP_DRY_RUN`: `"true"` logs only, `"false"` deletes. Accepts true/1/yes/on and false/0/no/off; anything else crashes the pod at startup (strict parsing since home-web-apps#258; older images treated any non-empty value as true).
- `CLEANUP_REPOSITORIES`: comma list of repos under `library/`. Currently the ten app repos (`blog, diagram-maker, fui-components, gluetun-sync, harbor-cleanup, homelab-api, backup-worker, home-hud, video-api, video-worker`) and the seven `<app>-base` repos. **`node-22-alpine` and `node-22-dev` must stay out**: their semver tags (`1.0.0`) are referenced by Dockerfiles/skaffold and would be classified `legacy` and deleted.
- `PROD_KEEP_COUNT: "5"`: newest prod tags kept per repo.

## What it keeps and deletes (per repo)

- Prod tags `YYYYMMDD-<run:5>-<pr:5>-<sha7>`: newest N kept, plus anything deployed in the cluster.
- `sha-<sha7>`: kept while an open PR heads at it or a surviving prod tag references it; otherwise deleted. Deleting a prod tag orphans its `sha-*`, so expect a second pass on the next run.
- `pr-<n>` / `pr-<n>-<sha7>`: kept for open PRs. `latest`: never deleted.
- **Anything else is `legacy` and deleted** unless deployed. Check a new repo's dry-run log for `legacy` tags before going live.
- Protection from the cluster covers images whose host is `HARBOR_HOST` (pods and workload templates of every kind). Images pulled from outside the cluster (compose files, other hosts) are not protected. If the cluster can't be read, the run aborts.

## Adding a repo

1. Check how its tags look and whether anything outside the cluster pulls them.
2. Dry-run PR (repo added + `CLEANUP_DRY_RUN: "true"`), restart the pod if needed, read the per-repo counts and every `legacy` and `sha-*` line.
3. Go-live PR (`"false"`). Stage by risk for big repos. Verify: pod log `Done. Deleted N, 0 error(s)`, all Deployments Ready, ImagePolicies still resolve.
