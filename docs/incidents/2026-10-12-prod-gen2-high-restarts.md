# prod-gen2: high restart counts (control plane + tigera-operator + external-dns)

Date: 2026-10-12. Cluster: `prod-gen2` (1 control plane `tf-prod-k8s-controller-1` 192.168.6.24, 3 workers, k8s v1.35.5).

## Summary

Restarts are **leader-election lost** exits, not crashes or OOMs. The apiserver (via etcd) intermittently fails to answer lease PUT/GETs within the 5s client timeout, mostly around **03:00-03:10 UTC**, which matches the Longhorn `daily-backups` RecurringJob (`0 3 * * *`, concurrency 2). Each controller that holds a lease (controller-manager, scheduler, tigera-operator) exits with code 1 and restarts.

Root cause is **strongly correlated, not proven**: Grafana MCP returned 401 (invalid API key) and etcd metrics port 2381 was unreachable from the dev box, so no fsync / apply-latency graphs were checked.

## Restart counts

| Pod | Restarts | Last exit | Cause |
|---|---|---|---|
| kube-controller-manager | 157 (144d) | 2026-10-11 03:01:54Z, exit 1 | `leaderelection lost`; lease PUT to apiserver `context deadline exceeded` |
| kube-scheduler | 149 (144d) | 2026-10-10 03:07:01Z, exit 1 | `Leaderelection lost`; lease GET/PUT `context deadline exceeded` |
| tigera-operator | 144 (144d) | 2026-10-11 03:02:01Z, exit 1 | `leader election lost`; PUT `leases/operator-lock` deadline exceeded |
| external-dns | 123 (91d) | 2026-10-07 14:46:43Z, exit 1 | `fatal: Failed to do run once: received bad gateway response (HTTP 502)` from the provider (Cloudflare) |
| external-dns-pihole | 103 (91d) | 2026-09-30 12:47:20Z, exit 255 `Unknown` | healthy logs up to the end; exit 255 with no error = container killed externally (likely etcd/apiserver event the same morning; etcd itself restarted 2026-09-30 12:46:57Z) |

~1 restart/day for the three leader-electing components over 144d lines up with a daily trigger.

## Evidence

- Controller-manager, scheduler and tigera-operator all fail with the same error shape: apiserver lease call times out at ~03:01-03:07 UTC.
- Daily Longhorn backups fire at 03:00 UTC: `daily-backups` RecurringJob, 12 volumes, concurrency 2 (backups created 03:01-03:02Z on 2026-10-12, one of 2.8 GB).
- Only CronJob-ish workload scheduled at 03:00 in the cluster is that Longhorn job.
- apiserver log (last 48h) shows etcd client retries `/etcdserverpb.KV/Range` failing at 03:05Z and 05:59Z on 10-12, and `http: Handler timeout` at 15:53Z (so it is not strictly confined to 03:00).
- etcd log shows `apply request took too long` (246-473 ms vs 100 ms expected) at 19:11Z on 10-12 on reads of Longhorn leases, tigera lease, `/registry/health`. etcd is slow under bursts of load.
- etcd itself is healthy otherwise: data-dir `/mnt/etcd` (dedicated disk), `--auto-compaction-mode=periodic --auto-compaction-retention=1h` already set, DB 153 MB, compaction ~60 ms, 3 restarts in 144d.
- Controller node: 3766 Mi used of 5.4 GiB allocatable (70%). apiserver 1513 Mi, etcd 279 Mi, controller-manager 114 Mi, scheduler 34 Mi. CPU is idle (5%). No OOM kills seen (exit code 1, not 137).
- etcd pod has `requests: cpu 100m, memory 100Mi` and no limits. apiserver has `requests: cpu 250m` only.
- No `Unhealthy` events cluster-wide.

## Likely causes (ranked)

1. **Disk/IO latency on the controller VM during the 03:00 backup burst.** Longhorn backup traffic (network + disk on the shared Proxmox host) delays etcd fsyncs and apiserver responses past the 5s lease timeout. Matches the earlier 2026-05-21 storage-contention incident and `home-playbooks/docs/plans/2026-05-21-split-ssd-etcd-longhorn.md`. etcd is on its own disk now, but the Proxmox host/controller (SATA SSD controller, thin pool) may still be shared.
2. **Controller VM memory pressure.** 70% used with 1.5 GiB apiserver; page cache for etcd's disk is limited at 5.4 GiB total. Less likely on its own, but worsens (1).
3. **Short leader-election timeouts.** Defaults (lease 15s, renew deadline 10s, retry 2s; client timeout 5s) leave little slack for 5s+ apiserver stalls. Makes a brief stall fatal for the process.

external-dns (Cloudflare 502) is a separate, unrelated provider-side issue; external-dns-pihole is probably collateral of the 09-30 etcd restart.

## Not yet verified (do before changing things)

- Grafana API key for the `grafana-prod` MCP needs rotating or fixing (401).
- `etcd_disk_wal_fsync_duration_seconds` p99 and `etcd_disk_backend_commit_duration_seconds` around 03:00 UTC for the last 7 days.
- Controller VM node-exporter: disk await/util and memory/page cache around 03:00.
- Proxmox: whether the controller VM's etcd disk and the Longhorn worker disks share the same physical device/controller.
- Whether pre-03:00 restarts happen on days with no backup (tests the correlation).

## Suggested changes (for `pbabbott/home-playbooks` unless noted)

1. **Relax leader election timeouts** (control plane static pods, kubeadm `extraArgs`):
   - `kube-controller-manager`: `--leader-elect-lease-duration=60s`, `--leader-elect-renew-deadline=40s`, `--leader-elect-retry-period=10s`
   - `kube-scheduler`: same three flags
   - Lets a ~30s apiserver stall pass without a restart. This stops the symptom. tigera-operator takes its own setting (Helm values in this repo) if available.
2. **Move the Longhorn backup off 03:00 and lower concurrency** (this repo: `daily-backups` RecurringJob, concurrency 2 -> 1, stagger across groups). Cheapest test of the correlation.
3. **etcd tuning in kubeadm `etcd.local.extraArgs`**, also bounding memory as you asked: `quota-backend-bytes` (e.g. 2 GiB), keep `auto-compaction`, optionally `heartbeat-interval`/`election-timeout` increases (single member, so low value). Leave a memory *limit* off etcd/apiserver, since an OOM kill is worse than bounded DB growth.
4. **Give the controller VM more RAM** (5.4 GiB allocatable at 70% is thin; 8 GiB) and set apiserver `--max-requests-inflight` / memory requests so the scheduler accounts for it.
5. **Storage isolation**: confirm etcd disk is on a physically separate device/controller from Longhorn, and consider Proxmox IO throttling on the Longhorn disks (see `home-playbooks` plan 2026-05-20).
6. **external-dns**: no action beyond optionally raising `--request-timeout`/backoff; 502s from Cloudflare are transient. Consider a liveness retry rather than `fatal`.

## Commands used

```bash
kubectl --context prod-gen2 get pods -A | grep -E "controller-manager|scheduler|tigera|external-dns|etcd|apiserver"
kubectl --context prod-gen2 -n <ns> logs <pod> --previous --tail=15
kubectl --context prod-gen2 -n kube-system logs etcd-tf-prod-k8s-controller-1 --since=48h
kubectl --context prod-gen2 -n longhorn-system get recurringjobs.longhorn.io,backups.longhorn.io
kubectl --context prod-gen2 top node
```
