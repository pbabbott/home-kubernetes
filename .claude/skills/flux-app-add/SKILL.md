---
name: flux-app-add
description: Add a new Helm-based application to prod-gen3 via Flux — namespace, HelmRepository, HelmRelease, HTTPRoute, kustomization overlay
---

Use when installing a new application into the gen3 cluster (`prod-gen3`) via GitOps. Gen1/gen2 are archived (`docs/archive/`).

## Directory layout

```
apps/
  base/<category>/<app>/
    <app>-ns.yaml
    <app>-helmrepository.yaml      # if chart not already in flux-system
    <app>-helmrelease.yaml
    <app>-httproute.yaml           # internal (pihole DNS)
    <app>-http-to-https-httproute.yaml
    kustomization.yaml
  prod-gen3/<category>/<app>/
    kustomization.yaml             # references ../../../base/<category>/<app>, patches hostname
```

`<category>` is one of the existing directories under `apps/base/` (ci-registry, dev-ai, host-proxies, media, platform, public-sites); add a new one only if none fits.

Add `- ./<category>/<app>` to `apps/prod-gen3/kustomization.yaml`, and add a row (Category, App, Summary) to the Apps table under "Workloads" in `README.md`.

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

No per-route `external-dns.alpha.kubernetes.io/target` annotation: external-dns ignores it, the target comes from the Gateway (`istio-ingress` = 192.168.6.29).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <app>
  labels:
    pihole-dns-enabled: "true"
spec:
  parentRefs:
    - name: istio-ingress
      namespace: istio-system
      sectionName: https
  hostnames:
    - "<app>.local.abbottland.io"
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

## prod-gen3 overlay kustomization

Put the real hostname directly in base — no patch needed:

```yaml
# apps/prod-gen3/<category>/<app>/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/<category>/<app>
```

If the app needs a gen3-specific hostname or settings, patch it in the overlay (JSON 6902):
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

| Internal (pihole) | Public (cloudflare) |
|-------------------|---------------------|
| `<app>.local.abbottland.io` | `<app>.abbottland.io` |

Public routes need only the label and `external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"` (the target comes from the Gateway). Public apps also need a NetworkPolicy and image update automation, see CLAUDE.md.

Internal routes → `istio-ingress` / `sectionName: https`
Public routes → `istio-ingress-public` / `sectionName: https-public` + label `external-dns-enabled: "true"`

## Validate before committing

```bash
kubectl kustomize apps/prod-gen3/<category>/<app> 2>&1
```

## Storage classes

| Class | Use for |
|-------|---------|
| `longhorn` (default) | Databases, app state, anything needing replication |
| `nas-storage` | Large shared files, media, caches |
