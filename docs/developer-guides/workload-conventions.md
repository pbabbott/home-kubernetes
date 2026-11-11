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

- Ingress: allow from the `istio-system` namespace only.
- Egress: deny all by default; add rules only for what the app needs (e.g. DNS to `kube-system`, PostgreSQL to the NAS at
  `192.168.4.124:5432`).

### Image update automation

- App-owned images (built in-house, mirrored to Harbor): `ImageRepository` + `ImagePolicy` + a
  `# {"$imagepolicy": "flux-system:<name>"}` marker on the deployment image field.
- Third-party images pulled directly from a public registry (e.g. ghcr.io): same pattern but omit `secretRef` on the
  `ImageRepository`.
- Helm-based apps: use a semver range in the `HelmRelease` `chart.spec.version` field (e.g. `>=6.0.0`).
- Examples: `apps/base/public-sites/umami/` (third-party) and `apps/base/public-sites/blog/` (in-house).

The global `ImageUpdateAutomation` lives at `clusters/prod-gen3/image-update-automation.yaml` and watches `./apps`. It is
SUSPENDED in the cluster (not in git) until PR builds can no longer reach prod via the ImagePolicies (see the loose ends
register in `docs/plans/2026-11-08-gen2-to-gen3-migration.md`). Do not unsuspend it.
