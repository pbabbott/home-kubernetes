# Istio MTU Investigation — 2026-05-10

## Goal
Debug a possible MTU issue in the Istio ambient mesh setup on the nonprod gen2 cluster.

## Findings

### MTU Stack
| Layer | MTU | Notes |
|-------|-----|-------|
| Physical `eth0` (node NIC) | 1500 | Standard ethernet |
| `vxlan.calico` | 1450 | -50 for VXLAN overhead, correct |
| Pod `cali*` interfaces | 1450 | Set explicitly via Calico Installation CR |
| Pod TCP MSS | ~1410 | 1450 - 40 (IP+TCP headers) |

- Calico Installation CR: `mtu: 1450`, `variant: Calico`, VXLAN mode
- Calico CNI configmap: `mtu: 0` (auto-detect) — overridden by Installation CR

### Istio Config
- Version: 1.25.5, ambient profile
- `ISTIO_META_ENABLE_HBONE: "true"` in istiod MeshConfig
- `INPOD_ENABLED: "true"` in ztunnel DaemonSet
- **No MTU settings anywhere** — all upstream defaults
- No TCPMSS clamping rules in istio-cni iptables

### Ambient Mesh Enrollment
- **No namespaces enrolled** — `istio.io/dataplane-mode=ambient` label absent on all namespaces
- Ztunnel is running on all 4 nodes but is effectively idle (no workload traffic)
- Ingress gateway runs as NodePort DaemonSet (30080/30443)

### Tests Run
- Ping w/ DF-bit at 1422 bytes payload (= 1450 total): **PASS** cross-node
- Ping w/ DF-bit at 1423 bytes payload (= 1451 total): **FAIL** "Message too large" — MTU boundary working correctly
- 10MB TCP transfer cross-node (worker-1 → worker-2): **PASS**
- TCP error counters (TCPMTUPFail, TCPRetransFail, drops): all **zero**

### Conclusion
**No active MTU problem.** Stack is correctly configured and healthy.

## Future Risk: Ambient Mesh Enrollment

When namespaces are enrolled in ambient mesh, ztunnel's HBONE tunnels run over node `eth0` (MTU 1500). HBONE adds ~50–100 bytes of TLS + HTTP/2 overhead per packet. With pod MTU at 1450 and no TCPMSS clamping, there's a potential fragmentation risk on the HBONE path.

**Mitigation options before enrolling ambient:**
1. Lower Calico MTU to 1400 (gives ztunnel headroom): set `mtu: 1400` in Calico Installation CR
2. Confirm ztunnel v1.25 does its own MSS clamping (likely, but untested here)
3. Add explicit TCPMSS clamping via istiod MeshConfig `proxyMetadata`

## Files Referenced
- `infra/base/istio/istiod-helm-release.yaml` — istiod HelmRelease (ambient profile, no MTU config)
- `infra/base/istio/ztunnel-helm-release.yaml` — ztunnel HelmRelease
- `infra/base/istio/istio-cni-helm-release.yaml` — CNI HelmRelease
- `.cursor/mtu-investigation.md` — user's manual investigation notes (pod MTU 1450, Proxmox host vmbr0 1500)
