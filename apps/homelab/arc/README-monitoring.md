# ARC Monitoring Setup

## Overview
This directory contains a ServiceMonitor configuration to enable Prometheus metrics scraping for the Actions Runner Controller (ARC).

## ServiceMonitor

The `arc-service-monitor.yaml` file configures Prometheus to scrape metrics from the ARC controller:

- **Service**: `arc-actions-runner-controller-metrics-service`
- **Port**: `metrics-port` (8443)
- **Scheme**: HTTPS
- **Interval**: 30 seconds
- **TLS**: Self-signed certificate (insecureSkipVerify: true)

### Labels
- `release: monitoring` - Matches Prometheus ServiceMonitorSelector to enable scraping

### Metrics Endpoint
The ServiceMonitor targets the ARC metrics service which exposes controller metrics including:
- Runner registration status
- Workflow run counts
- Autoscaler metrics
- Controller health metrics

## Verification

After FluxCD applies this ServiceMonitor, verify it's working:

1. **Check ServiceMonitor exists:**
   ```bash
   kubectl get servicemonitor -n arc
   ```

2. **Verify Prometheus is scraping:**
   - Access Prometheus UI: `prometheus.local.abbottland.io`
   - Navigate to Status → Targets
   - Look for `arc/arc-actions-runner-controller-metrics-service/0`

3. **Query metrics in Prometheus:**
   ```
   actions_runner_controller_runner_phase
   actions_runner_controller_workflow_runs
   ```

## Notes

- The metrics endpoint uses HTTPS with self-signed certificates, hence `insecureSkipVerify: true`
- Prometheus ServiceAccount should have permissions to scrape metrics automatically via kube-prometheus-stack RBAC
- Metrics are automatically collected and available in Grafana via the Prometheus datasource
