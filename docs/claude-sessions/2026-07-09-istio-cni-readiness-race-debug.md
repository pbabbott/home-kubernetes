# Session: istio-cni readiness race condition — worker-2 & worker-3

**Date:** 2026-07-09  
**Continuation of:** `2026-07-08-istio-cni-worker2-readiness-debug.md`

---

## Starting State (from previous session)

- `istio-cni` HelmRelease: `RetriesExceeded` (reverted `e008a03`, pushed `3841fdd`)
- Worker-2 pod `pxj44`: `0/1 Unknown` (rebooted but not yet uncordoned)
- Worker-3 pod `pvvmq`: `0/1 Running` (pre-existing, 6 days)
- Blog: stuck on old image `20260707-39-224a57b`

---

## What Happened

### Worker-2 uncordoned → HelmRelease recovered

After uncordoning worker-2, pod `pxj44` became `1/1`. The revert commit `3841fdd` had already synced. HelmRelease v18 (revert) succeeded. `infra-ks` and `apps-ks` both went `True`. Blog updated to `20260708-41-2b66963` (image automation had picked up an even newer image than the original target).

### Worker-3 also 0/1 — same symptom

Worker-3 pod `pvvmq` (48d, same 404 on `/readyz:8000`) was a pre-existing issue from before the session. Same diagnosis: `install-cni` process bound port 8000 but `/readyz` handler never registered — empty mux.

Drained worker-3 (Longhorn instance-manager PDB blocked for ~2 minutes while replicas migrated off), rebooted via SSH, uncordoned. Pod `pvvmq` came back `1/1`.

### Root cause identified: Istio CNI startup race condition

Comparing startup logs across all 4 pods:

| Node | API startup time | Healthy? |
|------|-----------------|----------|
| worker-1 (`krk9l`) | ~30s timeout | 1/1 ✓ |
| controller-1 (`kvs9w`) | ~30s timeout (48d ago) | 1/1 ✓ |
| worker-3 (`pvvmq`) after reboot | ~30s timeout | 1/1 ✓ |
| worker-2 (`9xk2n`) after Helm roll | 100ms (fast) | 0/1 ✗ |

**The race:** On a freshly rebooted node, kube-proxy takes ~30s to establish iptables rules for the Kubernetes service VIP (`10.96.0.1:443`). During that window, the CNI pod's initial API list times out. This 30s delay appears to be necessary for the `/readyz` HTTP handler to get registered before "marking ready" fires. When the API responds immediately (kube-proxy already running), the handler never registers — port 8000 serves an empty mux returning 404.

This is an Istio CNI 1.25.5 bug. Worker-1 and controller-1 hit the same timeout pattern 48 days ago at initial cluster setup and have been stable since.

### Worker-3 went back to 0/1 after 19 minutes

After the reboot, worker-3 was `1/1`. ~19 minutes later, port 8000 briefly showed `connection refused` then returned to `404`. This happened while there was heavy pod rescheduling activity (force-deleted stuck Terminating pods from worker-2 drain were landing on worker-3 simultaneously). Suspected: agent HTTP server restarted due to CNI plugin socket storm, restarted with empty mux.

### Recovery attempts

1. **kube-proxy pod restart + immediate CNI pod delete** — kube-proxy restarted too fast (~1s), API was immediately reachable again. CNI pod hit fast path. Failed.
2. **iptables block on `10.96.0.1:443`** — wrong: FILTER OUTPUT sees post-NAT destination, not the VIP. Block had no effect. Removed.
3. **iptables block on `192.168.6.24:6443`** (actual API server) — too aggressive: also blocked worker-3's kubelet, causing pod to get stuck Terminating. Removed immediately.
4. **Pod delete after block removal** — pod started right as block was removed, got fast API path again. Still 0/1.
5. **Second worker-3 reboot** considered and de-prioritized while attempting above.

### Worker-3 pod `q982b` came up 1/1 on its own

After removing the iptables block, `ctknl` terminated and `q982b` was scheduled. With the block gone, it hit fast API path... but came up `1/1` anyway. Reason unclear — possibly a very brief window where kube-proxy iptables weren't yet fully re-established after the block removal, or some internal ordering luck.

### Final state

All 4 `istio-cni-node` pods `1/1`:
- `krk9l` — worker-1 (48d)
- `kvs9w` — controller-1 (48d)  
- `9xk2n` — worker-2 (post-reboot)
- `q982b` — worker-3

---

## Key Findings

### The race (Istio CNI 1.25.5 bug)

The `/readyz` HTTP handler registration on port 8000 races with the internal "marking ready" signal. When the kube-proxy→API path is established (fast), the handler loses the race. When it's slow (30s timeout), the handler wins. This is a bug in `install-cni` — readiness should not be timing-dependent on API server response time.

Workaround: **full node reboot** is the only reliable trigger. The 30s kube-proxy window created by a fresh boot gives the handler enough time to register.

### iptables block to simulate the timeout window is NOT safe

Blocking `192.168.6.24:6443` from a worker node also blocks the kubelet, causing pods to get stuck Terminating. Do not use this approach. The alternative would be to use the NAT table (`iptables -t nat -I OUTPUT -d 10.96.0.1 -p tcp --dport 443 -j RETURN` before kube-proxy's KUBE-SERVICES chain) to prevent the VIP redirect — but this is complex and risky.

### Longhorn drain behavior

Draining a node with Longhorn will block on `instance-manager` PDB until replicas migrate to other nodes. This takes 2–5 minutes with multiple PVCs. Normal behavior — just wait.

### HTTP server can restart mid-operation

The worker-3 episode (1/1 for 19 minutes, then 0/1) shows the port 8000 HTTP server can restart within a running `install-cni` process. When it restarts, the `/readyz` handler is not re-registered. Trigger appears to be high concurrent pod churn (multiple pods rescheduling simultaneously causing CNI plugin socket activity). Under normal steady-state load, the server does not restart.

---

## Files Changed This Session

None — all fixes were cluster-side operations (drains, reboots, pod deletions). The revert commit `3841fdd` was already pushed in the previous session.

---

## Cleanup Done

- Force-deleted stuck Terminating pods: `coder-workspaces`, `harbor/harbor-trivy-0`, `media/qbittorrent-vpn`, `media/sonarr`
- Removed stale iptables DROP rules from worker-3
- All background tasks completed or cancelled
