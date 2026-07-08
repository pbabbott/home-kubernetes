
## Operational Guidelines

Be brief.

## Repository Folder Structure

This repository contains two sets of top-level directories, each tied to a different cluster generation:

### Gen 1 (homelab / "prod gen 1")
- `apps/` — application workloads deployed to the gen 1 cluster
- `infrastructure/` — infrastructure components (controllers, operators, etc.) for the gen 1 cluster
- Note: Gen1 cluster is dead. Only its code remains in this repository.

### Gen 2 (prod gen 2 & non-prod gen 2)
- `crds/` — CRD installs and CRD-layer Helm/releases per cluster path (e.g. `crds/non-prod-gen2/`)
- `applications/` — application workloads deployed to gen 2 clusters
- `infra/` — infrastructure components for gen 2 clusters (after CRDs are present)

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

## Reference

- `docs/bootstrap-flux-operator.md` — how to bootstrap Flux Operator on a fresh cluster (Ansible handoff)
- `docs/` — common operational processes: rotating secrets, maintenance tasks, etc.
- `docs/plans/` — implementation plans for migrations, features, or architectural changes — put new plans here
- `docs/claude-sessions/` — session summaries dumped by the `/dump` skill — put new session dumps here
- `docs/incidents/` — incident post-mortems and notes
- `.cursor/k8s-namespaces.md` — namespace inventory with storage class explanations

## AI Reference Docs

Docs prefixed `ai-reference-` in `docs/` are written for AI assistant use — step-by-step procedures, known gotchas, and copy-paste commands.

- `docs/ai-reference-infra.md` — cluster SSH targets, DNS patterns, Flux layering order, Longhorn backup targets
- `docs/ai-reference-op-connect-api-access.md` — query the op-connect vault API via port-forward; list vaults/items; known vault IDs
- `docs/ai-reference-onepassword-operator.md` — force-reconcile `OnePasswordItem` CRDs; debug secret key mismatches; common operator errors
- `docs/ai-reference-pihole-api.md` — pihole v5 API auth (SHA256 double-hash), A record and CNAME CRUD endpoints, debug pod pattern for cluster-internal access
- `docs/ai-reference-external-dns-pihole.md` — external-dns pihole config; why `registry: noop` is required; gateway annotation controls target (not HTTPRoute annotations); troubleshooting commands
- `docs/ai-reference-httproute-dns.md` — how HTTPRoutes wire to DNS; Cloudflare (public `*.non-prod.abbottland.io`) vs Pihole (local `*.local.non-prod.abbottland.io`); correct labels, annotations, and gateway sectionName per provider
