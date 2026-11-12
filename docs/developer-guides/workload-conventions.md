# Dev Guide - Workload Conventions

Rules to follow when adding or changing apps and infra in this repo. The step-by-step for adding an app is the
`flux-app-add` skill (`.claude/skills/flux-app-add/SKILL.md`).

## Keep the workload manifest current

`README.md` "Workloads" lists every app (`apps/prod-gen3`) and infra component (`infra/prod-gen3`, plus `crds/`) with a
Category and Summary. Whenever you add, remove or rename a workload, update those tables in the same change (rows sorted
by Category, then name). A Category is also a directory name, so put the new workload under an existing category dir
where one fits.

## Files and manifests

- Adding, changing or removing a script in `scripts/`: update the manifest in `scripts/CLAUDE.md` in the same commit (a pre-commit hook enforces the rows).
- Grafana dashboard JSON files must include `"gitops-managed"` in their `tags` array.
- Resource files are named `<name>-<kind>.yaml`, for example `haproxy-httproute.yaml` or `arc-ns.yaml`.
- Use `apiVersion: helm.toolkit.fluxcd.io/v2` for every `HelmRelease`. `v2beta1` and `v2beta2` were removed from the cluster.

## Publicly-facing apps

Any app with a Cloudflare/public HTTPRoute must have both of the following.

### NetworkPolicy

See `apps/base/public-sites/blog/blog-netpol.yaml` and `apps/base/public-sites/umami/umami-netpol.yaml` for examples.

- Required for every public app (any Cloudflare HTTPRoute), no exceptions: public workloads are locked down at the network level.
- Ingress: allow from the `istio-system` namespace only.
- Egress: deny all by default; add rules only for what the app needs (e.g. DNS to `kube-system`, PostgreSQL to the NAS at
  `192.168.4.124:5432`).
  Minimal egress, if any: scope each rule to a destination and port; avoid open-ended rules such as `443` to anywhere.

### Image update automation

- App-owned images (built in-house, mirrored to Harbor): `ImageRepository` + `ImagePolicy` + a
  `# {"$imagepolicy": "flux-system:<name>"}` marker on the deployment image field.
- Production tags from `home-web-apps` look like `YYYYMMDD-<RUN:5>-<PR:5>-<sha7>` (e.g. `20261111-00095-00253-1540400`).
  The policy is `filterTags.pattern: '^\d{8}-\d{5}-\d{5}-[a-f0-9]{7}$'` with `alphabetical: asc`; the zero-padded run
  number is what makes the alphabetical sort correct. PR builds only get `sha-<sha7>` and `pr-<n>`, so they can never
  match. See `home-web-apps/docs/dev-guide-publication.md`.
- Apps that show or log their running version also get an `IMAGE_TAG` env var kept in step with the image by a second
  setter on the value line: `value: <tag> # {"$imagepolicy": "flux-system:<name>:tag"}`. Both lines change in the same
  automation commit. The app reads it at runtime (`GET /api/version` or `/version`); never bake it into the build. Not
  needed for images that never read it (`fui-components` is static nginx).
- Third-party images pulled directly from a public registry (e.g. ghcr.io): same pattern but omit `secretRef` on the
  `ImageRepository`.
- Helm-based apps: use a semver range in the `HelmRelease` `chart.spec.version` field (e.g. `>=6.0.0`).
- Examples: `apps/base/public-sites/umami/` (third-party) and `apps/base/public-sites/blog/` (in-house).

The global `ImageUpdateAutomation` lives at `clusters/prod-gen3/image-update-automation.yaml` and watches `./apps`. It is
running (resumed 2026-11-11, home-kubernetes#39): when home-web-apps merges to `main` it commits the new tag to the
Deployment image line and the `IMAGE_TAG` line together (author `fluxcdbot`, one commit, one file per app). PR builds only
get `sha-<sha7>`/`pr-<n>` tags, which no policy matches. Never hand-edit those lines except to roll back or bootstrap;
to stop it: `flux --context prod-gen3 suspend image update apps` (suspension is cluster-only, not in git).
