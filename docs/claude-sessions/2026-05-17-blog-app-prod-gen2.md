# 2026-05-17 — Blog App Setup on prod-gen2

## What We Did

### New blog app deployed to prod-gen2 at `abbottland.io`

Created full app stack for a Next.js blog (`harbor.local.abbottland.io/library/blog`) on prod-gen2.

**Files created:**
- `applications/base/blog/` — base manifests (namespace, deployment, service, HTTPRoutes, image policy, regcred)
- `applications/prod-gen2/blog/kustomization.yaml` — overlay referencing base
- `applications/prod-gen2/kustomization.yaml` — added `./blog`
- `clusters/prod-gen2/image-update-automation.yaml` — `ImageUpdateAutomation` scanning `./applications`
- `clusters/prod-gen2/kustomization.yaml` — added `image-update-automation.yaml`

**Key decisions:**
- Public only — `abbottland.io` apex, no internal/local route
- No external-dns labels — apex domain managed by DDNS, not Cloudflare external-dns
- `imagePullPolicy: Always` + `# {"$imagepolicy": "flux-system:blog"}` marker for Flux image automation
- Semver policy `>=0.0.0` — picks up any version bump
- Port 3000 (Next.js)

### Gateway fix — apex domain listener

`istio-ingress-public` wildcard `*.abbottland.io` doesn't match apex. Added patch in `infra/prod-gen2/istio/kustomization.yaml`:
- New listener `https-public-apex` on port 443 for `abbottland.io`
- cert-manager auto-provisioned `apex-public-tls` via DNS-01 — issued, valid until 2026-08-15
- HTTPRoute updated to reference `sectionName: https-public-apex`

### ImageUpdateAutomation — first one for prod-gen2

Controllers (`image-reflector-controller`, `image-automation-controller`) were already running in the FluxInstance. Just needed the `ImageUpdateAutomation` resource wired in. Now observing both `blog:0.2.4` and `gluetun-sync:0.1.0`.

### media/regcred fix

Pre-existing `apps-ks` health check failure: `OnePasswordItem/media/regcred` stuck in `InProgress` with error `Cannot change secret type. Secret type is immutable`. Root cause: secret previously existed as `Opaque`, operator couldn't change it to `kubernetes.io/dockerconfigjson`.

Fix: deleted the secret, force-annotated the OnePasswordItem to trigger reconcile. Secret recreated, `Ready: True`. `apps-ks` health checks now unblocked.

**Known limitation:** The 1Password operator does not respect `operator.1password.io/type: kubernetes.io/dockerconfigjson` annotation — secrets are always created as `Opaque`. Both `media/regcred` and `blog/regcred` are Opaque. Pods currently running fine (harbor likely allows anonymous pulls or images node-cached).

## Current Status

- Blog pod: running ✓ (`blog:0.2.4`, 1 replica)
- HTTPRoute: accepted ✓ (`https-public-apex`)
- TLS cert: issued ✓
- Image automation: running ✓
- `abbottland.io` returning **404** — Next.js app-level TypeErrors in pod logs (`Cannot read properties of undefined`). Infrastructure is healthy; this is a bug in `blog:0.2.4`.

## Commits

- `7207461` — `feat(blog): add blog app to prod-gen2 at abbottland.io`
- `7108169` — `fix(blog): add apex listener to istio-ingress-public for abbottland.io`
