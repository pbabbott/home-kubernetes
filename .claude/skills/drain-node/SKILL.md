---
name: drain-node
description: Drain, reboot, and uncordon a gen2 cluster node — handles Longhorn PDB delays, SSH reboot, uncordon, and post-reboot DaemonSet pod cleanup (especially istio-cni-node).
---

Use when the user asks to reboot, drain, or cycle a specific node.

## SSH targets (from docs/ai-reference-infra.md)

| Node name | IP | Context |
|-----------|-----|---------|
| tf-prod-k8s-controller-1 | 192.168.6.24 | prod-gen2 |
| tf-prod-k8s-worker-1 | 192.168.6.25 | prod-gen2 |
| tf-prod-k8s-worker-2 | 192.168.6.26 | prod-gen2 |
| tf-prod-k8s-worker-3 | 192.168.6.27 | prod-gen2 |
| tf-nonprod-k8s-controller-1 | 192.168.6.31 | nonprod-gen2 |
| tf-nonprod-k8s-worker-1 | 192.168.6.32 | nonprod-gen2 |
| tf-nonprod-k8s-worker-2 | 192.168.6.33 | nonprod-gen2 |
| tf-nonprod-k8s-worker-3 | 192.168.6.34 | nonprod-gen2 |

SSH user: `firebolt`. Key auth only.

## Step 1: Confirm + set context

Ask the user which node. Determine the context (`prod-gen2` or `nonprod-gen2`) and IP from the table above. Set `CTX` and `NODE` variables before proceeding.

```bash
CTX=prod-gen2   # or nonprod-gen2
NODE=tf-prod-k8s-worker-3
IP=192.168.6.27
```

## Step 2: Warn user before draining

Tell the user:
- Drain will evict all non-DaemonSet pods from the node
- Longhorn PDB will block completion for **2–5 minutes** while replicas migrate off
- DaemonSet pods (istio-cni-node, calico-node, etc.) are NOT evicted — they stay until reboot

## Step 3: Drain

```bash
kubectl --context=$CTX drain $NODE --ignore-daemonsets --delete-emptydir-data 2>&1
```

Wait for this to complete. If it hangs on a PDB, that is expected — Longhorn instance-manager PDB blocks until volume replicas migrate. Just wait.

If drain fails with an error other than PDB blocking, investigate before proceeding.

## Step 4: SSH reboot

```bash
ssh -o StrictHostKeyChecking=no firebolt@$IP 'sudo reboot' 2>&1
```

The SSH session will drop immediately — that's expected.

## Step 5: Wait for node to go NotReady then come back Ready

```bash
# Wait for NotReady
until kubectl --context=$CTX get node $NODE 2>/dev/null | grep -q NotReady; do sleep 3; done
echo "Node went NotReady"

# Wait for Ready (with scheduling still disabled)
until kubectl --context=$CTX get node $NODE 2>/dev/null | grep -q "Ready,SchedulingDisabled"; do sleep 5; done
echo "Node is back Ready"
```

Timeout: allow up to 3 minutes for the node to return. If longer, investigate.

## Step 6: Uncordon

```bash
kubectl --context=$CTX uncordon $NODE
```

## Step 7: Force-delete stuck Unknown/Terminating pods

After a reboot, pods that were on the node may get stuck in Unknown or Terminating state. Force-delete them:

```bash
kubectl --context=$CTX get pods -A -o wide | awk -v node="$NODE" '$8==node && $4~/Unknown|Terminating/ {print $1, $2}' | \
  while read ns pod; do
    kubectl --context=$CTX delete pod -n "$ns" "$pod" --force --grace-period=0 2>&1
  done
```

## Step 8: Recycle the istio-cni-node pod on this node

**Critical:** The `install-cni` container has a readiness probe race condition (Istio CNI 1.25.5 bug). The pod that survived the reboot (or was running before drain) will be stuck 0/1 because it hit the fast kube-proxy path. The fresh reboot created a 30s kube-proxy window — exploit it by deleting the old pod immediately after uncordon so the new pod catches the window.

```bash
# Find and delete the istio-cni-node pod on this node
CNI_POD=$(kubectl --context=$CTX get pods -n istio-system -o wide | awk -v node="$NODE" '$7==node && /istio-cni-node/ {print $1}')
if [ -n "$CNI_POD" ]; then
  kubectl --context=$CTX delete pod -n istio-system "$CNI_POD"
  echo "Deleted $CNI_POD — waiting for replacement..."
  sleep 5
  kubectl --context=$CTX get pods -n istio-system | grep istio-cni-node
fi
```

Check that the new pod comes up 1/1. If it's 0/1, the timing window was missed. Options:
- Wait and delete again (may or may not help — depends on kube-proxy state)
- Repeat full drain+reboot cycle (reliable but slow)

## Step 9: Final health check

```bash
kubectl --context=$CTX get pods -A | awk 'NR>1 {split($3,a,"/"); if(a[1]!=a[2] && $4!~/Completed|Succeeded/) print}'
```

ContainerCreating and Init pods are expected for a few minutes post-uncordon. CrashLoopBackOff or persistent 0/1 Running warrant investigation.

## Known caveats

- **Longhorn drain delay**: instance-manager PDB blocks until replicas move off. Normal. Wait it out.
- **istio-cni-node race**: if new pod is 0/1 after step 8, the only reliable fix is a second full drain+reboot of the node.
- **DaemonSet pods survive drain**: `--ignore-daemonsets` skips eviction. They get killed by the OS reboot.
- **Control plane nodes**: draining a controller node will cause kube-apiserver, etcd, and scheduler to go offline briefly. Only do this if you know what you're doing and the cluster can tolerate downtime.
