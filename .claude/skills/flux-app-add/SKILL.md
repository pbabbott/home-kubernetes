---
name: flux-app-add
description: Add a new Helm-based application to prod-gen2 (or non-prod-gen2) via Flux — namespace, HelmRepository, HelmRelease, HTTPRoute, kustomization overlay
---

Use when installing a new application into a gen2 cluster via GitOps.

## Directory layout

```
applications/
  base/<app>/
    <app>-ns.yaml
    <app>-helmrepository.yaml      # if chart not already in flux-system
    <app>-helmrelease.yaml
    <app>-httproute.yaml           # internal (pihole DNS)
    <app>-http-to-https-httproute.yaml
    kustomization.yaml
  prod-gen2/<app>/
    kustomization.yaml             # references ../../base/<app>, patches hostname
```

Add `- ./<app>` to `applications/prod-gen2/kustomization.yaml`.

## Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app>
```

Note: if app uses Istio ambient mode, add `istio.io/dataplane-mode: ambient` label. If not ambient (most Helm apps), leave unlabeled — see podinfo-ns comment for why.

## HelmRepository

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <chart-name>
  namespace: flux-system
spec:
  interval: 24h
  url: https://<helm-repo-url>
```

Always in `flux-system` namespace.

## HelmRelease

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app>
  namespace: flux-system
spec:
  interval: 30m
  targetNamespace: <app>
  chart:
    spec:
      chart: <chart-name>
      version: ">=X.0.0"
      sourceRef:
        kind: HelmRepository
        name: <chart-name>
        namespace: flux-system
      interval: 24h
  values:
    service:
      type: ClusterIP
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 512Mi
```

Use `dependsOn` if the app needs another HelmRelease first (e.g. a database).

## HTTPRoute — internal only (pihole DNS, LAN)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <app>
  labels:
    pihole-dns-enabled: "true"
  annotations:
    external-dns.alpha.kubernetes.io/target: "192.168.6.28"
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-system
      sectionName: https
  hostnames:
    - "<app>.local.abbottland.io"    # prod-gen2
    # - "<app>.local.non-prod.abbottland.io"  # non-prod-gen2
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service-name>
          port: <port>
```

## HTTP→HTTPS redirect

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>-http-to-https
  namespace: <app>
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-system
      sectionName: http
  hostnames:
    - "<app>.local.abbottland.io"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

## Secrets via 1Password

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: <secret-name>
  namespace: <app>
  annotations:
    operator.1password.io/auto-restart: "true"
spec:
  itemPath: "vaults/Homelab/items/<Item Name>"
```

The shared NAS postgres credentials item: `vaults/Homelab/items/PostgreSQL NAS ASUSTOR`
— creates a secret with `username` and `password` keys.

To compose a PG connection URL from separate username/password keys, use K8s env var substitution:
```yaml
env:
  - name: PG_USER
    valueFrom:
      secretKeyRef:
        name: postgres-credentials
        key: username
  - name: PG_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-credentials
        key: password
  - name: DATABASE_URL
    value: "postgresql://$(PG_USER):$(PG_PASSWORD)@nas.local.abbottland.io/<dbname>?sslmode=disable"
```

## prod-gen2 overlay kustomization

Base hostname uses prod domain. If app is prod-only, put the real hostname directly in base — no patch needed:

```yaml
# applications/prod-gen2/<app>/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base/<app>
```

If deploying to both clusters, use a placeholder in base and patch per overlay:
```yaml
patches:
  - target:
      kind: HTTPRoute
      name: <app>
    patch: |-
      - op: replace
        path: /spec/hostnames/0
        value: <app>.local.abbottland.io
```

## Hostname conventions

| Cluster | Internal (pihole) | Public (cloudflare) |
|---------|-------------------|---------------------|
| prod-gen2 | `*.local.abbottland.io` | `*.abbottland.io` |
| non-prod-gen2 | `*.local.non-prod.abbottland.io` | `*.non-prod.abbottland.io` |

Internal routes → `istio-ingress` / `sectionName: https`
Public routes → `istio-ingress-public` / `sectionName: https-public` + label `external-dns-enabled: "true"`

## Validate before committing

```bash
kubectl kustomize applications/prod-gen2/<app> 2>&1
```

## Storage classes

| Class | Use for |
|-------|---------|
| `longhorn` (default) | Databases, app state, anything needing replication |
| `nas-storage` | Large shared files, media, caches |
