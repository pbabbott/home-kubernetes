# 2026-05-02 — Grafana Dashboard gitops-managed Tags

## What changed

- Added `"gitops-managed"` to `tags` array in three dashboard JSON files missing it:
  - `infra/base/kube-prometheus-stack/dashboards/haproxy.json`
  - `infra/base/kube-prometheus-stack/dashboards/harbor.json`
  - `infra/base/kube-prometheus-stack/dashboards/longhorn.json`
  - (`kubernetes-cluster-overview.json` and `my-hosts.json` already had it)

- Removed `gitops-managed: "true"` Kubernetes label from all 5 `configMapGenerator` entries in `infra/base/kube-prometheus-stack/kustomization.yaml` — label had no effect; tag in JSON is the correct convention.

- Added convention note to `CLAUDE.md`: Grafana dashboard JSON files must include `"gitops-managed"` in their `tags` array.
