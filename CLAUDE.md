
## Operational Guidelines

Be brief.

## Repository Folder Structure

This repository contains two sets of top-level directories, each tied to a different cluster generation:

### Gen 1 (homelab / "prod gen 1")
- `apps/` — application workloads deployed to the gen 1 cluster
- `infrastructure/` — infrastructure components (controllers, operators, etc.) for the gen 1 cluster
- Note: Gen1 cluster is dead. Only its code remains in this repository.

### Gen 2 (retired) and Gen 3 (live: `prod-gen3`)
- `crds/` — CRD installs and CRD-layer Helm/releases per cluster path (e.g. `crds/prod-gen3/`)
- `applications/` — application workloads; `base/` plus one overlay per cluster
- `infra/` — infrastructure components (after CRDs are present); `base/` plus one overlay per cluster
- `clusters/` — per-cluster Flux entry points
- Gen 3 (`prod-gen3`) is the only live cluster. Gen 2 (`prod-gen2`, `non-prod-gen2`) is retired and powered off; its overlays stay until the rollback window ends (~2026-12-07), see issue #35. Do not add anything to them.

## Working with the clusters

### Working with Flux

Instead of annotating resources, prefer to use `flux` on the command line - there is an mcp available for flux as well.

### Working with kubernetes

When issuing kubectl commands, you can simply using `kubectl` - there is no need for `ssh`

Additionally, `kubectx` is available to rapidly switch contexts.

## Conventions

- Grafana dashboard JSON files must include `"gitops-managed"` in their `tags` array.
- When working with resource files, use the convention `<name>-<kind>.yaml` 
  -  For example `haproxy-httproute.yaml` or `arc-ns.yaml` are acceptable. 
- Publicly-facing apps (any app with a Cloudflare/public HTTPRoute) must include a NetworkPolicy. See `applications/base/blog/blog-netpol.yaml` and `applications/base/umami/umami-netpol.yaml` for examples. Ingress: allow from `istio-system` namespace only. Egress: deny all by default; add rules only for what the app needs (e.g. DNS to `kube-system`, PostgreSQL to NAS at `192.168.4.124:5432`).
- Publicly-facing apps must have image update automation. For app-owned images (built in-house, mirrored to Harbor): `ImageRepository` + `ImagePolicy` + `# {"$imagepolicy": "flux-system:<name>"}` marker on the deployment image field. For third-party images pulled directly from a public registry (e.g. ghcr.io): same pattern but omit `secretRef` on the `ImageRepository`. For Helm-based apps: use a semver range in the `HelmRelease` `chart.spec.version` field (e.g. `>=6.0.0`). See `applications/base/umami/` (third-party) and `applications/base/blog/` (in-house) for examples. The global `ImageUpdateAutomation` resource lives at `clusters/prod-gen3/image-update-automation.yaml` and watches `./applications`. It is SUSPENDED in the cluster (not in git) until PR builds can no longer reach prod via the ImagePolicies (see the loose ends register in `docs/plans/2026-11-08-gen2-to-gen3-migration.md`): do not unsuspend it.

## Reference

- `docs/bootstrap-flux-operator.md` — how to bootstrap Flux Operator on a fresh cluster (Ansible handoff)
- `docs/` — common operational processes: rotating secrets, maintenance tasks, etc.
- `docs/plans/` — implementation plans for migrations, features, or architectural changes — put new plans here
- `docs/claude-sessions/` — session summaries dumped by the `/dump` skill — put new session dumps here
- `docs/incidents/` — incident post-mortems and notes
- `.cursor/k8s-namespaces.md` — namespace inventory with storage class explanations

## AI Reference Docs

Docs prefixed `ai-reference-` in `docs/` are written for AI assistant use — step-by-step procedures, known gotchas, and copy-paste commands.

- `docs/ai-reference-infra.md` — clusters and hosts (details in `home-playbooks/docs/HOSTS.md`), DNS patterns, Flux layering order, Longhorn backup targets
- `docs/ai-reference-op-connect-api-access.md` — query the op-connect vault API via port-forward; list vaults/items; known vault IDs
- `docs/ai-reference-gen3-manual-steps.md` — **read before adding a gen3 node or rebuilding gen3**: manual steps outside GitOps (Longhorn `node.longhorn.io/create-default-disk=true` node label, `/mnt/ssd` disk, NAS dirs, 1Password)
- `docs/ai-reference-secrets.md` — **start here for secrets (gen3)**: sealed-secrets only bootstraps 1Password; how to add a secret, key backup/rebuild, re-seal `op-credentials`, dev-shell `op` limits
- `docs/ai-reference-onepassword-operator.md` — force-reconcile `OnePasswordItem` CRDs; debug secret key mismatches; common operator errors
- `docs/ai-reference-pihole-api.md` — pihole v5 API auth (SHA256 double-hash), A record and CNAME CRUD endpoints, debug pod pattern for cluster-internal access
- `docs/ai-reference-external-dns-pihole.md` — external-dns pihole config; why `registry: noop` is required; gateway annotation controls target (not HTTPRoute annotations); troubleshooting commands
- `docs/ai-reference-httproute-dns.md` — how HTTPRoutes wire to DNS; Cloudflare (public `*.abbottland.io`) vs Pihole (local `*.local.abbottland.io`); correct labels, annotations, and gateway sectionName per provider
- `docs/ai-reference-gen3-data-move.md` — **read before moving an app's data gen2 → gen3**: Longhorn restore via `scripts/longhorn-restore.sh`, PVC binding rules, live-store safety, per-step rollback
