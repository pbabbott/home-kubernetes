# Session: prod-gen2 & nonprod-gen2 post-reboot recovery

**Date:** 2026-07-13

---

## Starting State

Both clusters had recently rebooted. Multiple pods stuck in Terminating or not healthy.

---

## What Was Fixed

### 1. etcd fragmentation (root cause of most issues)

**Prod-gen2 etcd:** 254 MB allocated, 33 MB in use — **87% fragmented**. Raft operations taking 200–600 ms vs 100 ms threshold. Caused cascade:
- `kube-apiserver` 0/1 (readiness probe returning 500 on `/readyz`)
- `kube-scheduler` crashing — leader election lease renewals timing out
- `kube-controller-manager` crashing — same
- `kube-state-metrics` CrashLoopBackOff — informer cache sync too slow

Fix:
```bash
etcdctl compact <current-revision>
etcdctl defrag
```
Result: **254 MB → 24 MB, 0% fragmentation**. All control plane pods recovered within ~2 minutes.

**Nonprod-gen2 etcd:** 68 MB allocated, 36 MB in use — **47% fragmented**. `kube-controller-manager` had 438+ restarts dating back to July 2.

Fix: same compact + defrag. Result: **68 MB → 20 MB, 0% fragmentation**. CM stabilized.

### 2. kube-state-metrics liveness probe (code fix)

KSM v2.15.0 returns 503 on `/livez` while informer caches sync. Default `initialDelaySeconds: 5` too short after cluster reboot with many resources. Pod crash-looped (14 restarts) before informers could sync.

Fix: `infra/base/kube-prometheus-stack/kube-prometheus-stack-helm-release.yaml` — added:
```yaml
kube-state-metrics:
  livenessProbe:
    initialDelaySeconds: 120
  readinessProbe:
    initialDelaySeconds: 120
```
Commit: `73e8461`. Applies to both clusters via base.

### 3. istio-cni-node worker-3 (Istio CNI 1.25.5 race bug)

Pod `istio-cni-node-q982b` on `tf-prod-k8s-worker-3` had been 0/1 for 4d16h (same bug documented in 2026-07-09 session). The July 2026 reboot of workers 1 & 2 did not include worker-3.

Fix:
1. `kubectl drain tf-prod-k8s-worker-3 --ignore-daemonsets --delete-emptydir-data`
2. `ssh firebolt@192.168.6.27 'sudo reboot'`
3. Waited for node Ready
4. `kubectl uncordon tf-prod-k8s-worker-3`
5. `kubectl delete pod -n istio-system istio-cni-node-4k2rn` (old pod; new one `l25tw` came up 1/1)

### 4. Stuck Unknown/Terminating pods (post-drain cleanup)

After worker-3 drain+reboot, several pods stuck in Unknown state (Longhorn, istio-ingress, etc.). Force-deleted:
```bash
kubectl get pods -A -o wide | awk '$8=="tf-prod-k8s-worker-3" && $4~/Unknown|Terminating/ {print $1, $2}' | \
  while read ns pod; do kubectl delete pod -n "$ns" "$pod" --force --grace-period=0; done
```

### 5. drain-node skill created

New skill at `.claude/skills/drain-node/SKILL.md`. Commit: `37884e5`.

Covers:
- SSH target table (prod + nonprod gen2 nodes → IPs)
- Drain with `--ignore-daemonsets --delete-emptydir-data`
- SSH reboot
- Wait for NotReady → Ready
- Uncordon
- Force-delete stuck Unknown/Terminating pods
- istio-cni-node race condition workaround (delete pod after uncordon to catch kube-proxy window)

---

## Known Remaining Issues

### nonprod-gen2: tigera-operator CrashLoopBackOff (41 days)

`tigera-operator-5f74fb764-dgx98` crashes every ~80s losing its leader election lease to `10.96.0.1:443` with `context deadline exceeded`. 126+ restarts. Pre-dates today's work. Calico data plane still functional (cluster networking works). Root cause unknown — suspected issue with service VIP reachability or operator lease timeout config. Needs separate investigation.

---

## Key Findings

### etcd fragmentation accumulates post-reboot

After a cluster reboot, all controllers restart simultaneously and flood etcd with LIST operations. Combined with existing fragmentation from normal operations, this causes raft ops to spike to 200–600 ms and cascade into lease renewal failures across control plane components.

**Runbook:** On any post-reboot instability, check etcd `PERCENTAGE NOT IN USE` first:
```bash
etcdctl endpoint status -w table
```
If >20%, compact + defrag immediately.

### etcd defrag procedure (prod-gen2)
```bash
kubectl exec -n kube-system etcd-tf-prod-k8s-controller-1 -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  compact $(kubectl exec -n kube-system etcd-tf-prod-k8s-controller-1 -- \
    etcdctl ... endpoint status -w json | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['Status']['header']['revision'])")

kubectl exec -n kube-system etcd-tf-prod-k8s-controller-1 -- \
  etcdctl ... defrag
```

### istio-cni-node race (confirmed again)

Same Istio CNI 1.25.5 bug. Pod delete alone (without reboot) hit fast kube-proxy path → 0/1 again. Full node drain+reboot required to get the 30s kube-proxy window. Documented in both 2026-07-08 and 2026-07-09 sessions.

---

## Files Changed

| File | Change |
|------|--------|
| `infra/base/kube-prometheus-stack/kube-prometheus-stack-helm-release.yaml` | Added KSM probe `initialDelaySeconds: 120` |
| `.claude/skills/drain-node/SKILL.md` | New skill — node drain/reboot procedure |
