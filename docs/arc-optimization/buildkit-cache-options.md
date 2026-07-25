# BuildKit Cache — Options and Recommendation

## Problem
dind runner `/var/lib/docker` is `emptyDir` — dies with pod. Every run re-pulls base
layers and re-executes unchanged build stages. No layer cache survives between jobs.

## What This Fixes (vs Prior Work)

| Layer | Problem | Status |
|-------|---------|--------|
| npm install | NFS contention on pnpm store | Done — migrated to NAS NFS |
| Docker pulls | IO spike from concurrent layer pulls | Done — max-concurrent-downloads: 2 |
| Docker build steps | Full rebuild every run, no layer cache | This doc |

---

## Option A — Registry Cache via Harbor (Recommended)

Store BuildKit cache as OCI manifests in Harbor. Harbor already exists, LAN bandwidth.

### Setup
1. Create project `buildcache` in Harbor (or reuse `library`)
2. Add `docker buildx create --use` to CI job setup step
3. Add cache flags to each `docker buildx build` invocation:

```bash
docker buildx build \
  --cache-from type=registry,ref=harbor.local.abbottland.io/library/buildcache/myapp \
  --cache-to   type=registry,ref=harbor.local.abbottland.io/library/buildcache/myapp,mode=max \
  -t harbor.local.abbottland.io/library/myapp:tag \
  .
```

`mode=max` exports all intermediate layers, not just the final image — best cache hit rate.

### What changes in CI
- Workflows using `docker build` → switch to `docker buildx build`
- If there's a shared `docker-build` reusable workflow, one place to update
- Add a `docker buildx create --use` step before the build step

### Trade-offs
- **Pro:** Shared across all 5 dind runners; survives pod restarts; no extra PVC
- **Pro:** Harbor storage only; all traffic is LAN
- **Con:** Harbor storage grows — needs a retention/cleanup policy on the `buildcache` project
- **Con:** First run after a base image change will be slow (cache miss); subsequent runs fast
- **Con:** Requires `docker buildx`, not plain `docker build`

---

## Option B — GHA Cache Backend (actions-cache-server)

`actions-cache-server` is already deployed and `CUSTOM_ACTIONS_RESULTS_URL` is already set
on runner pods. BuildKit has a `gha` cache type that speaks the same Actions cache API.

```bash
docker buildx build \
  --cache-from type=gha \
  --cache-to   type=gha,mode=max \
  .
```

### Trade-offs
- **Pro:** Zero new infrastructure — reuses existing cache server
- **Pro:** Automatic TTL (cache entries expire with job scope)
- **Con:** Need to verify `falcondev-oss/actions-runner` image exposes BuildKit GHA cache
  vars (`ACTIONS_CACHE_URL`, `ACTIONS_RUNTIME_TOKEN`) to the docker buildx process
- **Con:** `actions-cache-server-data` PVC is 30Gi RWO Longhorn — becomes new single bottleneck
  if Docker layer cache fills it; would need expansion + potential migration like pnpm store

---

## Option C — Local NAS PVC Cache

Mount NAS PVC at `/cache`, use `--cache-to type=local,dest=/cache`.

- **Not recommended.** Brings NFS IO back for Docker layer data (heavy sequential writes).
  Worse than registry cache; same NFS contention pattern as old pnpm store.

---

## Recommendation

Implement **Option A (Harbor registry cache)**.

Priority order for implementation:
1. Create Harbor `buildcache` project (Harbor UI or Terraform/API)
2. Update CI `docker-build` reusable workflow to use `docker buildx build` with cache flags
3. Add Harbor cleanup policy for `buildcache` project (e.g. keep last 5 tags per repo)
4. Monitor Harbor storage growth after rollout

Option B worth revisiting if Harbor storage becomes a concern — but validate the
`falcondev-oss/actions-runner` BuildKit GHA cache integration first.
