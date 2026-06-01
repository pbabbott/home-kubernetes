---
name: grafana-analyze
description: Analyze a Grafana dashboard URL for a specific concern (IO, CPU, memory, network, etc.)
---

User will provide a Grafana dashboard URL and a concern. Follow these steps exactly.

## Step 1: Parse the URL

Extract from query params:
- `var-namespace` → namespace
- `var-pod` → pod name
- `var-cluster` → cluster (may be empty)
- `from` / `to` → time range (e.g. `now-1h` / `now`)
- Dashboard UID from path: `/d/<UID>/`

Convert `from`/`to` to epoch seconds for Prometheus range queries:
```bash
NOW=$(date +%s)
# now-1h → $((NOW - 3600)), now-3h → $((NOW - 10800)), now-6h → $((NOW - 21600)), now-24h → $((NOW - 86400))
```

## Step 2: Determine Grafana instance

| URL pattern | Instance | Base URL |
|-------------|----------|----------|
| `grafana.local.abbottland.io` | prod | `https://grafana.local.abbottland.io` |
| `grafana.local.non-prod.abbottland.io` | non-prod | `https://grafana.local.non-prod.abbottland.io` |

Auth: `admin:admin` (basic auth via `-u "admin:admin"`)  
Datasource UID for Prometheus: `prometheus` (verified on both instances)

## Step 3: Run queries in parallel

Use this shell function pattern — run all queries in one Bash call:

```bash
POD="<pod>"
NS="<namespace>"
NOW=$(date +%s)
START=$((NOW - 3600))  # adjust per time range
BASE="https://grafana.local.abbottland.io"  # or non-prod

qrange() {
  local label="$1" query="$2" divisor="${3:-1}" unit="${4:-}"
  curl -sk -u "admin:admin" \
    "$BASE/api/datasources/proxy/uid/prometheus/api/v1/query_range" \
    --data-urlencode "query=$query" \
    --data-urlencode "start=$START" \
    --data-urlencode "end=$NOW" \
    --data-urlencode "step=60" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
results=d.get('data',{}).get('result',[])
if not results:
    print('$label: No data')
else:
    for r in results:
        vals=[float(v[1]) for v in r['values']]
        div=$divisor
        print(f'$label: min={min(vals)/div:.2f} avg={sum(vals)/len(vals)/div:.2f} max={max(vals)/div:.2f} $unit (n={len(vals)})')
"
}
```

## Step 4: Query sets by concern

### IO concern
```bash
qrange "Disk R KB/s"  "sum(irate(container_fs_reads_bytes_total{namespace=\"$NS\",pod=\"$POD\"}[5m])) by (pod)"  1024 "KB/s"
qrange "Disk W KB/s"  "sum(irate(container_fs_writes_bytes_total{namespace=\"$NS\",pod=\"$POD\"}[5m])) by (pod)" 1024 "KB/s"
qrange "Net RX KB/s"  "sum(irate(container_network_receive_bytes_total{namespace=\"$NS\",pod=\"$POD\"}[5m])) by (pod)" 1024 "KB/s"
qrange "Net TX KB/s"  "sum(irate(container_network_transmit_bytes_total{namespace=\"$NS\",pod=\"$POD\"}[5m])) by (pod)" 1024 "KB/s"
```

### CPU concern
```bash
qrange "CPU cores"    "sum(irate(container_cpu_usage_seconds_total{namespace=\"$NS\",pod=\"$POD\",container!=\"\"}[5m])) by (pod)" 1 "cores"
qrange "CPU throttle" "sum(irate(container_cpu_cfs_throttled_seconds_total{namespace=\"$NS\",pod=\"$POD\",container!=\"\"}[5m])) / sum(irate(container_cpu_cfs_periods_total{namespace=\"$NS\",pod=\"$POD\",container!=\"\"}[5m])) * 100" 1 "%"
# Get CPU limit for context
qrange "CPU limit"    "sum(kube_pod_container_resource_limits{namespace=\"$NS\",pod=\"$POD\",resource=\"cpu\"}) by (pod)" 1 "cores"
```

### Memory concern
```bash
qrange "Mem WS MiB"   "sum(container_memory_working_set_bytes{namespace=\"$NS\",pod=\"$POD\",container!=\"\"}) by (pod)" 1048576 "MiB"
qrange "Mem RSS MiB"  "sum(container_memory_rss{namespace=\"$NS\",pod=\"$POD\",container!=\"\"}) by (pod)" 1048576 "MiB"
qrange "Mem limit MiB" "sum(kube_pod_container_resource_limits{namespace=\"$NS\",pod=\"$POD\",resource=\"memory\"}) by (pod)" 1048576 "MiB"
```

### General / unknown concern — run all
Run IO + CPU + Memory query sets above.

## Step 5: Supplement with resource limits/requests (always useful)

```bash
# Instant query for current limits
curl -sk -u "admin:admin" \
  "$BASE/api/datasources/proxy/uid/prometheus/api/v1/query" \
  --data-urlencode "query=kube_pod_container_resource_limits{namespace=\"$NS\",pod=\"$POD\"}" \
  --data-urlencode "time=$NOW" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('data',{}).get('result',[]):
    m=r['metric']; print(m.get('container'), m.get('resource'), r['value'][1])
"
```

## Step 6: Output format

Present as markdown table + narrative. Always include:
- Table: metric | min | avg | max | unit
- Call out spikes (max >> avg indicates burst)
- Compare against limits if available
- Flag anything >80% of limit as warning
- Note if data is sparse (n < 10) — pod may have been short-lived

## Notes

- `container!=""` filter excludes pause/infra containers
- Ephemeral runner pods (ARC) have short lifetimes — low `n` is expected
- Disk write spikes during builds are normal but check if node storage is Longhorn (can be slow under write pressure)
- No data on throttle metric = no CPU limit set on pod
- `step=60` gives 1-min resolution; use `step=300` for 24h+ windows to avoid huge result sets
