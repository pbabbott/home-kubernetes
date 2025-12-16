# Monitoring Namespace Setup

## Overview
The `monitoring` namespace hosts a comprehensive observability stack managed via FluxCD HelmReleases.

## Components

### 1. kube-prometheus-stack (v70.2.1)
**HelmRelease:** `monitoring`  
**Chart:** `kube-prometheus-stack` from `prometheus-community` repo

#### Prometheus
- Ingress: `prometheus.local.abbottland.io` (TLS, whitelisted)
- Additional scrape configs for physical node exporters:
  - `dumbledore` (192.168.4.157:9100)
  - `chimaera` (192.168.4.192:9100)
  - `room_of_requirement` (192.168.4.124:9100)
  - `bananapi` (192.168.4.144:9100)

#### Grafana
- Ingress: `grafana.local.abbottland.io` (TLS, whitelisted)
- Default dashboards enabled
- Timezone: `America/Chicago`
- Data sources:
  - Prometheus (default, via `prometheus-operated.monitoring.svc.cluster.local:9090`)
  - Loki (`http://loki.monitoring.svc:3100`)

#### Alertmanager
- Ingress: `alertmanager.local.abbottland.io` (TLS, whitelisted)

### 2. Loki (v6.29.0)
**HelmRelease:** `loki`  
**Chart:** `loki` from `grafana` repo

- Deployment mode: SingleBinary
- Storage: Filesystem (10Gi PVC on Longhorn)
- Schema: v13 with TSDB index (24h period)
- Ingress: `loki.local.abbottland.io` (TLS, whitelisted)
- Service: `loki.monitoring.svc:3100`
- Chunks cache: 1024MB allocated memory

### 3. OpenTelemetry Collector (v0.120.0)
**HelmRelease:** `opentelemetry-collector`  
**Chart:** `opentelemetry-collector` from `opentelemetry-helm` repo

- Mode: DaemonSet
- Image: `otel/opentelemetry-collector-contrib`
- Receivers:
  - OTLP (gRPC + HTTP)
  - Filelog (collects all pod logs, excludes own logs and Loki logs)
- Exporters:
  - OTLP HTTP → Loki (`http://loki.monitoring.svc:3100/otlp`)
  - Prometheus Remote Write → Prometheus (`http://prometheus.monitoring.svc:8889`)
- Pipelines:
  - Metrics: OTLP → Prometheus Remote Write
  - Logs: Filelog → OTLP HTTP → Loki

## ServiceMonitors

- **ingress-nginx**: Scrapes metrics from ingress-nginx controller (30s interval)
- **arc-actions-runner-controller**: Scrapes metrics from Actions Runner Controller (30s interval, HTTPS with TLS verification disabled)

## Access Control

All ingresses are:
- Whitelisted to private IP ranges: `10.0.0.0/8, 192.168.0.0/16, 172.20.0.0/12, 10.244.0.0/16`
- TLS enabled via cert-manager (`letsencrypt-prod` issuer)
- Using `nginx` ingress class

## Data Flow

1. **Metrics**: Kubernetes resources + physical nodes → Prometheus
2. **Logs**: Pod logs → OpenTelemetry Collector → Loki
3. **Visualization**: Grafana queries Prometheus (metrics) and Loki (logs)
4. **Alerts**: Alertmanager handles Prometheus alerts
