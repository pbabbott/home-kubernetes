# Session: istio-cni worker-2 readiness failure & blog deploy unblock

**Date:** 2026-07-08  
**Trigger:** Blog in prod running old image `20260707-39-224a57b`, should be `20260708-40-31949c6`

---

## Root Cause Chain

```
blog deployment (old image)
  ← apps-ks blocked: "dependency infra-ks not ready"
    ← infra-ks blocked: "HelmRelease/flux-system/istio-cni status: Failed"
      ← istio-cni HelmRelease: RetriesExceeded, upgrade timed out
        ← DaemonSet istio-cni-node rollout stuck
          ← pod on worker-2 (0/1): readiness probe 404 on /readyz:8000
```

---

## What We Found

### istio-cni DaemonSet state
- Pods on worker-1, controller-1, worker-3: `1/1 Running`, ~48d old
- Pod on worker-2: `0/1 Running`, ~20h old (created during failed Helm upgrade)
- All nodes same kernel: worker-1/worker-2 on `6.8.0-124-generic`, worker-3/controller-1 on `6.8.0-134-generic`

### Readiness probe behavior on worker-2
- `GET /readyz:8000` → `HTTP 404 Not Found` ("Not Found", 10 bytes)
- `GET /healthz:8000` → `HTTP 404 Not Found`
- Worker-1 (healthy): `/readyz` → `200 OK`, `/healthz` → `200 OK`
- Process owning port 8000: `install-cni` (correct pod's PID, verified via cgroup UID match)
- ControlZ (port 9876): works fine — Istio admin UI loads
- Metrics (port 15014): works fine — `istio_cni_install_ready 1` (CNI reports itself ready!)
- Conclusion: `install-cni` starts HTTP server on port 8000 but **never registers `/readyz` or `/healthz` handlers** — server is a completely empty mux

### Node-level state on worker-2
- Stale iptables/ipset residues detected on every pod restart:
  - `ip6tables-nft` ISTIO_POSTRT chain (left by previous pods)
  - ipsets `istio-inpod-probes-v4` / `istio-inpod-probes-v6` (in use by legacy iptables rules)
  - IPv4 iptables-legacy ISTIO_POSTRT chain
- Pod logs: `"Found residues of old iptables rules/chains, reconciliation is recommended  component=host"`
- Pod logs: `"reconcile is needed but no-reconcile flag is set"` (for `component=host`, NOT pod-level)
- Despite residues, pod continues startup: ztunnel connects, CNI config installed, all looks healthy
- `"CNI ambient server marking ready"` IS logged — but HTTP handlers never bind

### What we tried (and why it didn't work)
1. **`flux reconcile helmrelease istio-cni --reset`** × 2 — both timed out (5m), same DaemonSet rollout failure
2. **Manually patched configmap** `AMBIENT_RECONCILE_POD_RULES_ON_STARTUP: false → true` — pod still 404
3. **Deleted failing pod** multiple times (d4x5n → 9cnx9 → xqq9s → pxj44) — each restart same result
4. **Flushed ip6tables-nft ISTIO_POSTRT chain** — pod recreates it; no effect on readiness
5. **Flushed iptables-legacy ISTIO_POSTRT chain** (via `nsenter -t 1 -m -u -i -n -p` with host mount namespace) — ipsets still in use, `ipset` binary not on host
6. **Netshoot `ipset destroy`** — ipsets report "does not exist" but reappear / unclear state
7. **Suspended istio-cni HelmRelease** — `infra-ks` health check still sees `status: Failed`, no help
8. **Rejected `wait: false` on HelmRelease** — papers over the problem, not a real fix

---

## Key Insight (Working Theory)

Commit `e008a03` added `reconcilePodRulesOnStartup: true` to the HelmRelease. This triggered a Helm upgrade which rolled the DaemonSet, replacing the worker-2 pod first. The new pod fails immediately.

**Before `e008a03`:** All 4 pods healthy 48d  
**After `e008a03` + Helm upgrade:** worker-2 pod fails, others untouched (upgrade stopped mid-rollout)

With `AmbientReconcilePodRulesOnStartup: true`:
- "inpod reconcile mode enabled" is logged
- The CNI scans all pods on the node and reconciles their iptables rules on startup
- If this reconciliation **fails silently** on some pod on worker-2, the readiness HTTP handler may never get registered

The other 3 pods still run with `false` (never restarted — Helm stopped rolling after worker-2 failed). They register `/readyz` normally.

`reconcilePodRulesOnStartup` was an attempt to fix a "no-reconcile" warning for `component=host`, but that warning is about **host-level** rules. The setting only controls **pod-level** (inpod) reconciliation — wrong fix for the warning.

---

## Decided Action

Revert `e008a03`: remove `reconcilePodRulesOnStartup: true` from HelmRelease, reverting to default (`false`). Also revert manual configmap patch. Resume HelmRelease, let Flux re-apply, worker-2 pod should restart with `false` and register `/readyz` normally.

**Remaining:** If worker-2 still fails after revert (meaning it's a true node-state issue independent of the setting), next step is `kubectl drain tf-prod-k8s-worker-2 --ignore-daemonsets` + node reboot via Ansible/SSH.

---

## Files Changed This Session

- `infra/base/istio/istio-cni-helm-release.yaml` — reverting `reconcilePodRulesOnStartup: true` (added by `e008a03`, now removed)
- Manual cluster-side: configmap `istio-system/istio-cni-config` patched `AMBIENT_RECONCILE_POD_RULES_ON_STARTUP: true` (needs reverting via Helm reconcile)
- Manual cluster-side: `istio-cni` HelmRelease suspended (needs resuming)
