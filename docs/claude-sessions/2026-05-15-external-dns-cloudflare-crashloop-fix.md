# Session: external-dns Cloudflare CrashLoopBackOff Fix

**Date:** 2026-05-15  
**Cluster:** prod-gen2

## Problem

`external-dns` deployment in `external-dns` namespace was 0/1 (CrashLoopBackOff, 486 restarts). Root cause was compound:

1. `tf-prod-k8s-worker-1` was `NotReady` (kubelet stopped posting status ~00:46 UTC). The stuck pod was on that node, preventing rescheduling.
2. After force-deleting the pod to reschedule, the new pod still crashed immediately on a healthy node — so the node issue was masking an underlying app bug.

## Root Cause

`external-dns` (Cloudflare provider) was creating an A record for `podinfo.abbottland.io` with target `192.168.6.28` (HAProxy private IP) and `--cloudflare-proxied` enabled. Cloudflare rejects proxied records pointing to private IPs (error 9003). This caused a `fatal` log line and process exit every sync cycle.

**Why 192.168.6.28?**  
The `istio-ingress` Gateway has annotation `external-dns.alpha.kubernetes.io/target: 192.168.6.28`. For gateway-httproute source, the gateway annotation takes priority over all other target sources (including HTTPRoute-level annotations). So all records used the private IP as the A record target.

**Why A records at all?**  
The HelmRelease had `managedRecordTypes: [CNAME]` in values, but the chart (external-dns 1.15.0) merges this with defaults rather than replacing — runtime config showed `[A AAAA CNAME]`. The CNAME-only restriction was silently ineffective.

## Fix

Moved `--managed-record-types=CNAME` into `extraArgs` (bypasses the broken values key), removing the `managedRecordTypes` values field entirely.

**File:** `infra/base/external-dns/external-dns-helm-release.yaml`

```yaml
# Before
managedRecordTypes:
  - CNAME
extraArgs:
  - --cloudflare-proxied
  - --label-filter=external-dns-enabled=true

# After
extraArgs:
  - --cloudflare-proxied
  - --label-filter=external-dns-enabled=true
  - --managed-record-types=CNAME
```

With CNAME-only enforced:
- No A records attempted → no Cloudflare 9003 error → no crash
- CNAME `podinfo.abbottland.io → abbottland.io` created correctly (from HTTPRoute annotation)

**Commit:** `08a5c20` — `fix(external-dns): enforce CNAME-only via extraArgs for cloudflare provider`

## Outcome

- `external-dns` pod: 1/1 Running, 0 restarts post-fix
- `external-dns-pihole`: unaffected, remained 1/1 throughout
- `tf-prod-k8s-worker-1`: still NotReady — needs separate investigation

## Key Architecture Note

For gateway-httproute source, target resolution order:
1. Gateway annotation `external-dns.alpha.kubernetes.io/target` — wins
2. Gateway `status.addresses` — fallback

HTTPRoute-level target annotations are **ignored**. Both external-dns instances (cloudflare + pihole) read from the same `istio-ingress` gateway. The CNAME-only managedRecordTypes is what prevents cloudflare from attempting A records using the gateway's private IP annotation.
