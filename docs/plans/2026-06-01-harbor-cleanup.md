DEPLOY-HANDOFF.md

# harbor-cleanup — Flux Deployment Handoff

---

## Flux Deployment — What Was Created

Files added to this repo under `applications/base/harbor-cleanup/` and wired into `applications/prod-gen2/`:

| File | Purpose |
|------|---------|
| `namespace.yaml` | `harbor-cleanup` namespace |
| `regcred-onepassworditem.yaml` | Image pull secret from Harbor admin 1Password item |
| `harbor-credentials-onepassworditem.yaml` | Secret `harbor-credentials` — keys `username`, `password` |
| `github-pat-onepassworditem.yaml` | Secret `github-pat` — key `github_pat` |
| `harbor-cleanup-serviceaccount.yaml` | ServiceAccount for in-cluster pod listing |
| `harbor-cleanup-clusterrole.yaml` | ClusterRole `harbor-cleanup-pod-reader` (pods: list) |
| `harbor-cleanup-clusterrolebinding.yaml` | Binds ClusterRole to ServiceAccount |
| `harbor-cleanup-configmap.yaml` | Non-secret env vars (host, repos, cron, TZ, etc.) |
| `harbor-cleanup-image-repository.yaml` | Flux ImageRepository scanning `library/harbor-cleanup` |
| `harbor-cleanup-image-policy.yaml` | Date-based tag policy (`\d{8}-\d+-[a-f0-9]{7}`, alphabetical asc) |
| `harbor-cleanup-deployment.yaml` | Deployment — `envFrom` ConfigMap + explicit `env` for secret keys |
| `harbor-cleanup-service.yaml` | ClusterIP Service port 80 → 4030 |
| `harbor-cleanup-httproute.yaml` | HTTPS route: `harbor-cleanup.local.abbottland.io` (pihole DNS) |
| `harbor-cleanup-http-to-https-httproute.yaml` | HTTP → HTTPS redirect |
| `harbor-cleanup-servicemonitor.yaml` | Prometheus scrape at `/metrics` every 60s |
| `prod-gen2/harbor-cleanup/kustomization.yaml` | Overlay referencing base |

`applications/prod-gen2/kustomization.yaml` updated to include `./harbor-cleanup`.

**Note on secrets:** Two separate OnePasswordItems feed into the Deployment via explicit `env.valueFrom.secretKeyRef` entries (not `envFrom`) because the 1Password field labels (`username`, `password`, `github_pat`) differ from the required env var names (`HARBOR_USERNAME`, `HARBOR_PASSWORD`, `GITHUB_TOKEN`).

**Note on initial image tag:** Deployment seeds with placeholder tag `20260601-0-0000000`. Pod will be in `ImagePullBackOff` until first real image is pushed to Harbor — Flux image automation then updates the tag automatically.

---


## Overview

Express.js service that runs on a cron schedule to delete stale tags from the Harbor container registry. It cross-references GitHub Actions workflow runs and currently deployed Kubernetes pod images to protect tags that are still in use.

**Image**: `harbor.local.abbottland.io/library/harbor-cleanup:<version>`  
**Port**: `4030`  
**Namespace**: `harbor-cleanup`

---

## HTTP Routes

| Method | Path       | Purpose                                                        |
| ------ | ---------- | -------------------------------------------------------------- |
| `GET`  | `/healthz` | Liveness / readiness probe — returns `200 OK`                  |
| `GET`  | `/status`  | JSON: current schedule, last run result, next run time         |
| `POST` | `/cleanup` | Trigger an immediate manual cleanup run                        |
| `GET`  | `/metrics` | Prometheus text exposition (same data as `/status`, as gauges) |

---

## Environment Variables

### Plain (non-secret) — put in ConfigMap or Deployment env

| Variable                  | Default           | Required | Notes                                                                                      |
| ------------------------- | ----------------- | -------- | ------------------------------------------------------------------------------------------ |
| `PORT`                    | `4030`            | No       | HTTP listen port                                                                           |
| `SHOW_CONFIG`             | `false`           | No       | Logs config on startup (masks secrets)                                                     |
| `HARBOR_HOST`             | —                 | **Yes**  | e.g. `harbor.local.abbottland.io`                                                          |
| `GITHUB_OWNER`            | —                 | **Yes**  | e.g. `pbabbott`                                                                            |
| `GITHUB_REPO`             | —                 | **Yes**  | e.g. `home-web-apps`                                                                       |
| `CLEANUP_REPOSITORIES`    | —                 | **Yes**  | Comma-separated list, e.g. `blog,diagram-maker,fui-components,gluetun-sync,harbor-cleanup` |
| `PROD_KEEP_COUNT`         | `5`               | No       | Most-recent production images to keep per repo                                             |
| `CLEANUP_CRON_EXPRESSION` | `0 3 * * *`       | **Yes**  | Standard cron — must be valid                                                              |
| `TZ`                      | `America/Chicago` | **Yes**  | Timezone for cron evaluation                                                               |

### Secret — inject from ExternalSecret / 1Password Operator

| Variable          | 1Password Vault | Item Name                            | Field        |
| ----------------- | --------------- | ------------------------------------ | ------------ |
| `HARBOR_USERNAME` | Homelab         | `harbor.local.abbottland.io - admin` | `username`   |
| `HARBOR_PASSWORD` | Homelab         | `harbor.local.abbottland.io - admin` | `password`   |
| `GITHUB_TOKEN`    | Homelab         | `Github PAT`                         | `github_pat` |

---

## 1Password Items Required

Both items already exist in the **Homelab** vault (they are also used by the local dev env via `abctl secrets generate-env`). No new items need to be created — just reference them in your `OnePasswordItem` or `ExternalSecret` CRDs.

```
Vault: Homelab
  Item: "harbor.local.abbottland.io - admin"
    username  → HARBOR_USERNAME
    password  → HARBOR_PASSWORD

  Item: "Github PAT"
    github_pat → GITHUB_TOKEN
```

---

## Kubernetes RBAC

The app uses `@kubernetes/client-node` with in-cluster config to call `listPodForAllNamespaces()`. This prevents deletion of any image tag currently running in the cluster.

You need a **ServiceAccount + ClusterRole + ClusterRoleBinding**:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: harbor-cleanup
  namespace: <your-namespace>
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: harbor-cleanup-pod-reader
rules:
  - apiGroups: ['']
    resources: ['pods']
    verbs: ['list']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: harbor-cleanup-pod-reader
subjects:
  - kind: ServiceAccount
    name: harbor-cleanup
    namespace: <your-namespace>
roleRef:
  kind: ClusterRole
  name: harbor-cleanup-pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Wire the ServiceAccount into the Deployment via `spec.template.spec.serviceAccountName: harbor-cleanup`.

> If RBAC is unavailable or the ServiceAccount has no pod-list permission, the app degrades gracefully — it logs a warning and skips the deployed-image protection check rather than crashing.

---

## Deployment Sketch

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: harbor-cleanup
  namespace: <your-namespace>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: harbor-cleanup
  template:
    metadata:
      labels:
        app: harbor-cleanup
    spec:
      serviceAccountName: harbor-cleanup
      containers:
        - name: harbor-cleanup
          image: harbor.local.abbottland.io/library/harbor-cleanup:0.1.0
          ports:
            - name: http
              containerPort: 4030
          envFrom:
            - configMapRef:
                name: harbor-cleanup-config
            - secretRef:
                name: harbor-cleanup-secret
          livenessProbe:
            httpGet:
              path: /healthz
              port: 4030
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /healthz
              port: 4030
            initialDelaySeconds: 5
            periodSeconds: 10
```

---

## Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: harbor-cleanup
  namespace: <your-namespace>
spec:
  selector:
    app: harbor-cleanup
  ports:
    - name: http
      port: 80
      targetPort: 4030
```

---

## HTTPRoute

Assumes a Gateway named `gateway` in your cluster (adjust `parentRefs` to match your setup):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: harbor-cleanup
  namespace: <your-namespace>
spec:
  parentRefs:
    - name: gateway
      namespace: <gateway-namespace>
  hostnames:
    - harbor-cleanup.local.abbottland.io
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: harbor-cleanup
          port: 80
```

---

## Metrics / Observability

`GET /metrics` exposes Prometheus gauge metrics (no `prom-client` dependency — plain text exposition format). Metrics emitted:

| Metric | Description |
|--------|-------------|
| `harbor_cleanup_info{cron_expression,timezone}` | Static config info gauge |
| `harbor_cleanup_last_run_start_timestamp_seconds` | Unix timestamp of last run start |
| `harbor_cleanup_last_run_end_timestamp_seconds` | Unix timestamp of last run end |
| `harbor_cleanup_last_success_timestamp_seconds` | Unix timestamp of last success |
| `harbor_cleanup_last_failure_timestamp_seconds` | Unix timestamp of last failure |
| `harbor_cleanup_last_run_duration_ms` | Last run duration in ms |
| `harbor_cleanup_last_run_total_deleted` | Tags deleted in last run |
| `harbor_cleanup_last_run_total_errors` | Errors in last run |

Timestamp metrics and result metrics are **omitted** (not emitted as NaN) before the first run completes.

Wire up a `ServiceMonitor`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: harbor-cleanup
  namespace: <your-namespace>
spec:
  selector:
    matchLabels:
      app: harbor-cleanup
  endpoints:
    - port: http
      path: /metrics
      interval: 60s
```

---

## Image Updates (Flux ImagePolicy)

If you use Flux image automation, the semver filter `0.1.x` or `>=0.1.0` will track patch releases. The image is published to `harbor.local.abbottland.io/library/harbor-cleanup`.

---

## Checklist for the Flux Repo

- [ ] `Namespace` (if new)
- [ ] `ServiceAccount` + `ClusterRole` + `ClusterRoleBinding`
- [ ] `OnePasswordItem` or `ExternalSecret` → `Secret` named `harbor-cleanup-secret`
- [ ] `ConfigMap` named `harbor-cleanup-config` (non-secret env vars)
- [ ] `Deployment` (references both, sets `serviceAccountName`)
- [ ] `Service`
- [ ] `HTTPRoute` to `harbor-cleanup.local.abbottland.io`
- [ ] DNS record for `harbor-cleanup.local.abbottland.io` → cluster ingress IP (if not wildcard)
- [ ] Kustomization / HelmRelease wired into your Flux source
