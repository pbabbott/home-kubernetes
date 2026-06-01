# Incident: Harbor proxy cache unusable as Docker daemon mirror

**Date:** 2026-06-01  
**Status:** Resolved  
**Severity:** Low (builds degraded, not down — fell back to direct Docker Hub pulls)

---

## Summary

After implementing the ARC dind registry mirror plan
(`docs/plans/2026-06-01-arc-dind-registry-mirror.md`), the `docker-build`
GitHub Actions job failed at the `docker/setup-buildx-action` step with:

```
ERROR: Error response from daemon: error walking manifest for
docker.io/moby/buildkit:buildx-stable-1: descriptor is neither a manifest or index
```

Root cause: a structural incompatibility between Docker daemon's
`registry-mirrors` path format and Harbor's project-based registry API path
format.

---

## Root Cause

### Docker daemon mirror path format

When Docker daemon is configured with:

```json
{
  "registry-mirrors": ["https://harbor.local.abbottland.io/proxy-dockerhub"]
}
```

Docker treats the full mirror URL as a base and appends the registry v2 API
path **after** the path component of the mirror URL:

```
https://harbor.local.abbottland.io/proxy-dockerhub/v2/moby/buildkit/manifests/buildx-stable-1
                                    ^^^^^^^^^^^^^^^^ ^^^
                                    mirror path      Docker appends /v2/ here
```

### Harbor project-based API path format

Harbor's registry API uses project names as the **first path segment after `/v2/`**:

```
https://harbor.local.abbottland.io/v2/proxy-dockerhub/moby/buildkit/manifests/buildx-stable-1
                                    ^^^ ^^^^^^^^^^^^^^^^
                                    v2/ Harbor project is part of repo name
```

### Result

Docker sends `GET /proxy-dockerhub/v2/...` → Harbor routes this to its web UI
(HTTP 200 `text/html`). Docker receives HTML where it expects an OCI manifest,
producing the "descriptor is neither a manifest or index" error.

Manifest fetches appeared to partially work during the initial investigation
because some requests short-circuit, but blob downloads always returned HTML,
causing the eventual failure.

Confirmed by direct comparison:

| Path | Response |
|------|----------|
| `/v2/proxy-dockerhub/moby/buildkit/blobs/sha256:fe29...` | `application/json 404` (correct: not cached yet) |
| `/proxy-dockerhub/v2/moby/buildkit/blobs/sha256:fe29...` | `text/html 200` (wrong: Harbor web UI) |

---

## Resolution

Added two `URLRewrite` rules to the Harbor `HTTPRoute`
(`applications/base/harbor/httproute.yaml`) that rewrite the Docker daemon
mirror path format to Harbor's expected format:

```
/proxy-dockerhub/v2/{rest}  →  /v2/proxy-dockerhub/{rest}
/proxy-ghcr/v2/{rest}       →  /v2/proxy-ghcr/{rest}
```

These rules use Gateway API `ReplacePrefixMatch` and are placed before the
catch-all `/` rule so they take precedence.

After the rewrite, `GET /proxy-dockerhub/v2/` returns `application/json 401`
(Harbor's standard auth challenge) instead of `text/html 200`, which is the
correct behavior for an anonymous pull against a public Harbor project.

**Commits:**
- `806cd4d` — initial mirror plan implementation
- `1ada557` — remove broken mirror (interim fix while investigating)
- `b3afb74` — add HTTPRoute path rewrites + restore mirror in daemon.json

---

## Why This Is Non-Obvious

1. Docker's `registry-mirrors` documentation does not explicitly state how
   path components in the mirror URL are handled. The behavior (appending
   `/v2/` after the path, not before) is an implementation detail.

2. Harbor's proxy cache feature is documented as a pull-through cache for
   explicit pulls (`docker pull harbor.host/proxy-project/image:tag`), not
   as a drop-in `registry-mirrors` target. Using it as a daemon mirror
   requires the URL rewrite layer described here.

3. The error message (`descriptor is neither a manifest or index`) points to
   a manifest parsing failure, not an HTTP routing failure, which obscures
   the actual root cause.

4. The manifest endpoint partially "worked" (returned HTML with HTTP 200)
   while blob endpoints failed the same way — so the failure appeared to be
   at the blob layer rather than the routing layer.

---

## Path Rewrite Reference

The Gateway API `HTTPRoute` rules that make daemon mirrors work with Harbor:

```yaml
rules:
  - matches:
      - path:
          type: PathPrefix
          value: /proxy-dockerhub/v2
    filters:
      - type: URLRewrite
        urlRewrite:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: /v2/proxy-dockerhub
    backendRefs:
      - name: harbor
        port: 80

  - matches:
      - path:
          type: PathPrefix
          value: /proxy-ghcr/v2
    filters:
      - type: URLRewrite
        urlRewrite:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: /v2/proxy-ghcr
    backendRefs:
      - name: harbor
        port: 80

  # catch-all (existing rule)
  - matches:
      - path:
          type: PathPrefix
          value: /
    backendRefs:
      - name: harbor
        port: 80
```

For each new Harbor proxy project added in the future, add a corresponding
`URLRewrite` rule following the same pattern before the catch-all rule.
