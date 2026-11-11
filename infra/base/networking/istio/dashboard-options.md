
# Istio Monitoring

ServiceMonitor and PodMonitors for all Istio Ambient mesh components.

## Monitors

| File | Kind | Component | Port | Path |
|------|------|-----------|------|------|
| `istiod-service-monitor.yaml` | ServiceMonitor | istiod | 15014 | `/metrics` |
| `istio-ingress-pod-monitor.yaml` | PodMonitor | ingress gateway | 15090 | `/stats/prometheus` |
| `ztunnel-pod-monitor.yaml` | PodMonitor | ztunnel | 15020 | `/stats/prometheus` |
| `istio-cni-pod-monitor.yaml` | PodMonitor | istio-cni | 15014 | `/metrics` |

## Grafana Dashboards

### istiod (`istiod-service-monitor.yaml`)

| ID | Name | Downloads |
|----|------|-----------|
| [7645](https://grafana.com/grafana/dashboards/7645-istio-control-plane-dashboard/) | Istio Control Plane Dashboard | 63.7M |
| [11829](https://grafana.com/grafana/dashboards/11829-istio-performance-dashboard/) | Istio Performance Dashboard | 37.1M |

### Ingress Gateway (`istio-ingress-pod-monitor.yaml`)

| ID | Name | Downloads |
|----|------|-----------|
| [7636](https://grafana.com/grafana/dashboards/7636-istio-service-dashboard/) | Istio Service Dashboard | 60.7M |
| [7630](https://grafana.com/grafana/dashboards/7630-istio-workload-dashboard/) | Istio Workload Dashboard | 54.7M |

### ztunnel (`ztunnel-pod-monitor.yaml`)

| ID | Name | Downloads |
|----|------|-----------|
| [21306](https://grafana.com/grafana/dashboards/21306-istio-ztunnel-dashboard/) | Istio Ztunnel Dashboard | 534K |
| [7639](https://grafana.com/grafana/dashboards/7639-istio-mesh-dashboard/) | Istio Mesh Dashboard | 57.9M |

### istio-cni (`istio-cni-pod-monitor.yaml`)

No dedicated CNI dashboard exists. The CNI node agent exposes port 15014 (`/metrics`) covering network plugin lifecycle metrics. Closest options:

| ID | Name | Downloads |
|----|------|-----------|
| [7645](https://grafana.com/grafana/dashboards/7645-istio-control-plane-dashboard/) | Istio Control Plane Dashboard | 63.7M |
| [11829](https://grafana.com/grafana/dashboards/11829-istio-performance-dashboard/) | Istio Performance Dashboard | 37.1M |

All dashboards sourced from [grafana.com/orgs/istio/dashboards](https://grafana.com/orgs/istio/dashboards).
