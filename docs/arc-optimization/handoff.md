# CI Wall-Clock Optimization Handoff

Source: [run 30161094166, job 89697285125](https://github.com/pbabbott/home-web-apps/actions/runs/30161094166/job/89697285125) (video-api CI, PR #179)

Total wall clock: ~8295s. Actual job work: ~2900s. Rest is dead/serialized time.

## #1 — 98-minute dead gap (14:39:40 → 16:18:01)

Zero jobs running GitHub-side during this window. Confirmed via `gh run list` that no other workflow run was active/competing at the time — so this isn't queue contention from other PRs/branches. Points at `prod-gen2-dind-runner` self-hosted pool going unavailable (node offline, autoscaler scaled to zero and slow to wake, etc).

This single gap accounts for ~70% of total wall clock. Biggest lever by far — fix this before anything else below.

**Action:** check runner pool health / autoscaler config / node status for that window on the cluster side (see home-web-apps `docs/dev-guide-cluster-access.md` for controller access).

## #2 — Runner pool serializes even when healthy

14:21–14:39 window: `fui-components-ui-tests` + `unit-tests(logger)` briefly run 2-wide, then `blog-ui-tests` → `docker-build(fui-components)` → `unit-tests(abctl)` → `unit-tests(video-db)` run one-at-a-time back-to-back — durations sum almost exactly to elapsed wall time. Implies only ~1-2 concurrent `dind`-labeled runner slots exist, while the matrix fan-out is ~14 jobs (9 `docker-build` + 5 `unit-tests`) all competing for that same pool.

**Done (home-kubernetes):** raised `maxRunners` 5 → 9 (`applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`); bumped ResourceQuota pods 20 → 25, CPU 28 → 32, memory 80Gi → 100Gi (`applications/base/arc/arc-runners-resourcequota.yaml`). Covers all 9 docker-build jobs in parallel. Node scheduling headroom verified (~25Gi requests vs 47Gi allocatable across 3 workers).

## #3 — No pnpm store cache across jobs

`.github/actions/pnpm-setup/action.yaml:30-32` sets `store-dir` but never persists it via `actions/cache`. Every one of ~20 jobs in the run does a cold `pnpm install --frozen-lockfile` (~2-3min each — e.g. `format` job: 2m9s just for install). Runners are ephemeral, so nothing persists between jobs.

**Already done (home-kubernetes):** both runner types mount a shared NFS PVC at `/home/runner/.local/share/pnpm/store` (`arc-pnpm-store` PVC). Packages installed by any job persist on the NFS volume and are available to subsequent jobs — no `actions/cache` needed. Verify `store-dir` in `.github/actions/pnpm-setup/action.yaml` still points to `/home/runner/.local/share/pnpm/store`.

## #4 — No concurrency cancellation

`ci.yml` has no `concurrency:` group. Rapid pushes to the same PR/branch spawn overlapping full runs that compete for the scarce dind pool instead of the stale run getting cancelled.

**Action:**
```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

## #5 — Consider splitting runner labels

Plain `unit-tests` jobs don't need Docker-in-Docker the way `docker-build`/`integration-tests`/`smoke-tests` do, but they all share the `prod-gen2-dind-runner` label/pool. Dedicating a separate non-dind pool for unit-tests would stop them competing with docker-build for the same scarce dind slots.

**Infra already exists (home-kubernetes):** `prod-gen2-amd64-runner` (non-dind, maxRunners=8) is deployed alongside the dind pool. Action needed in **home-web-apps** only: change `unit-tests` job `runs-on` label from `prod-gen2-dind-runner` → `prod-gen2-amd64-runner`.

## Already in good shape (no action needed)

- Harbor buildx registry cache (`--cache-from`/`--cache-to type=registry`) — wired in `packages/abctl/src/docker-cli/docker-commands.ts:68-72`, enabled per-app via each `abctl.yml`'s `buildCache` key.
- Turbo remote cache — `TURBO_TOKEN`/`TURBO_API`/`TURBO_TEAM` already wired in `ci.yml`.

## Priority order

1. Runner pool availability gap (#1) — ~10x bigger than everything else combined.
2. Runner pool replica count (#2).
3. pnpm store cache (#3).
4. Concurrency cancellation (#4).
5. Runner label split (#5) — lower urgency, structural.
