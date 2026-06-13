# CrowdSec: k8s LAPI + Istio Behavioral Detection

**Repo:** home-kubernetes  
**Goal:** Deploy CrowdSec LAPI + agent in both gen2 clusters. Agent reads Istio gateway access logs to detect behavioral threats (scanners, brute force, CVE probers). LAPI serves ban decisions to the HAProxy firewall bouncer and any in-cluster bouncers.

**Deploy non-prod first** to validate Istio log parsing and XFF IP handling before enabling live bans in prod.

---

## Architecture

```
Istio Gateway pods
      │ access logs
      ▼
CrowdSec Agent (DaemonSet)
      │ detects threats
      ▼
CrowdSec LAPI (Deployment) ◄── community blocklist sync
      │
      ├── HAProxy firewall bouncer (pulls decisions → iptables DROP at edge)
      └── (optional) in-cluster bouncer for k8s NetworkPolicy bans
```

---

## Repo Implementation Map

Uses the standard `infra/base` + cluster overlay pattern.

### Files to create

```
infra/base/crowdsec/
  crowdsec-namespace.yaml
  crowdsec-helm-repo.yaml
  crowdsec-helm-release.yaml     # agent + lapi values
  kustomization.yaml

infra/non-prod-gen2/crowdsec/
  kustomization.yaml             # references base; no NodePort (no HAProxy bouncer)

infra/prod-gen2/crowdsec/
  kustomization.yaml             # references base; patches NodePort + enrollment key
```

### Wire into cluster kustomizations

Add `./crowdsec` to:
- `infra/non-prod-gen2/kustomization.yaml`
- `infra/prod-gen2/kustomization.yaml`

### Istio access logging

`infra/base/istio/istiod-helm-release.yaml` currently only has `profile: ambient` — no `meshConfig`.
Add a patch to inject `meshConfig.accessLogFile` + JSON format. Since both clusters need identical logging config, patch the base file directly (not per-cluster overlay).

### Secret management

No k8s secret needed for the HAProxy bouncer key. HAProxy runs on an LXC outside the cluster — it only needs the key in its own config (`terraform.tfvars` in `home-playbooks`). The key never lives in the cluster.

Sequence:
1. Deploy LAPI via GitOps
2. `kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers add haproxy-bouncer` → copy key
3. Set `crowdsec_bouncer_api_key` in `home-playbooks` `terraform.tfvars` → `terraform apply`

---

## Step 1: Configure Istio access logs

CrowdSec agent needs structured access logs from the Istio ingress gateway. Enable JSON access logging in the Istio mesh config (or via `IstioOperator`):

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    accessLogFile: /dev/stdout
    accessLogFormat: |
      {"authority":"%REQ(:AUTHORITY)%","bytes_received":"%BYTES_RECEIVED%","bytes_sent":"%BYTES_SENT%","duration":"%DURATION%","method":"%REQ(:METHOD)%","path":"%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%","protocol":"%PROTOCOL%","request_id":"%REQ(X-REQUEST-ID)%","requested_server_name":"%REQUESTED_SERVER_NAME%","response_code":"%RESPONSE_CODE%","response_flags":"%RESPONSE_FLAGS%","route_name":"%ROUTE_NAME%","start_time":"%START_TIME%","upstream_cluster":"%UPSTREAM_CLUSTER%","upstream_host":"%UPSTREAM_HOST%","user_agent":"%REQ(USER-AGENT)%","x_forwarded_for":"%REQ(X-FORWARDED-FOR)%"}
    accessLogEncoding: JSON
```

The `x_forwarded_for` field is the real client IP (set by Cloudflare). CrowdSec must ban on this IP, not the Cloudflare proxy IP.

Patch target in `infra/base/istio/istiod-helm-release.yaml`:

```yaml
# add under spec.values:
meshConfig:
  accessLogFile: /dev/stdout
  accessLogEncoding: JSON
  accessLogFormat: |
    {"authority":"%REQ(:AUTHORITY)%","bytes_received":"%BYTES_RECEIVED%","bytes_sent":"%BYTES_SENT%","duration":"%DURATION%","method":"%REQ(:METHOD)%","path":"%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%","protocol":"%PROTOCOL%","request_id":"%REQ(X-REQUEST-ID)%","requested_server_name":"%REQUESTED_SERVER_NAME%","response_code":"%RESPONSE_CODE%","response_flags":"%RESPONSE_FLAGS%","route_name":"%ROUTE_NAME%","start_time":"%START_TIME%","upstream_cluster":"%UPSTREAM_CLUSTER%","upstream_host":"%UPSTREAM_HOST%","user_agent":"%REQ(USER-AGENT)%","x_forwarded_for":"%REQ(X-FORWARDED-FOR)%"}
```

---

## Step 2: Deploy CrowdSec via Helm

```bash
helm repo add crowdsec https://crowdsecurity.github.io/helm-charts
helm repo update
```

`values.yaml`:

```yaml
container_runtime: containerd

agent:
  acquisition:
    - namespace: istio-system
      podName: istio-ingressgateway-*
      program: istio   # uses crowdsecurity/istio collection parser
  env:
    - name: COLLECTIONS
      value: "crowdsecurity/istio crowdsecurity/base-http-scenarios"

lapi:
  env:
    - name: ENROLL_KEY        # optional — links to app.crowdsec.net dashboard
      value: ""               # fill in if you want the console
    - name: SCENARIOS
      value: "crowdsecurity/http-crawl-non_statics crowdsecurity/http-bad-user-agent crowdsecurity/http-path-traversal-probing"

service:
  type: NodePort
  nodePort: 32080             # HAProxy LXC connects here
```

These values go into `infra/base/crowdsec/crowdsec-helm-release.yaml` as a Flux `HelmRelease`. The `service.nodePort: 32080` patch applies only in `infra/prod-gen2/crowdsec/` — non-prod omits it.

```bash
# manual install for initial testing only; use HelmRelease for GitOps
helm install crowdsec crowdsec/crowdsec -n crowdsec --create-namespace -f values.yaml
```

---

## Step 3: Generate HAProxy bouncer API key

```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli bouncers add haproxy-bouncer
# Copy the output key — used in home-playbooks terraform.tfvars as crowdsec_bouncer_api_key
```

---

## Step 4: Verify agent sees Istio logs

```bash
kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli metrics
# Should show log lines parsed from istio-ingressgateway pods

kubectl exec -n crowdsec deploy/crowdsec-lapi -- cscli alerts list
# Will populate as threats are detected
```

---

## Step 5: (Optional) In-cluster bouncer

If you want bans enforced inside the cluster as well (NetworkPolicy-level):

```bash
helm install crowdsec-k8s-bouncer crowdsec/crowdsec-helm-charts \
  --set "bouncer.crowdsec_lapi_url=http://crowdsec-service.crowdsec:8080" \
  --set "bouncer.crowdsec_lapi_key=<key from cscli bouncers add k8s-bouncer>"
```

---

## After k8s setup — return to home-playbooks

With LAPI running and HAProxy bouncer key in hand, complete `2026-06-11-crowdsec-haproxy-bouncer.md`:

1. Add `crowdsec_lapi_url = "http://192.168.6.2x:32080"` to `terraform.tfvars`
2. Add `crowdsec_bouncer_api_key` to `terraform.tfvars`
3. `terraform apply`

---

## IP Chain Analysis

```
Internet client → Cloudflare → HAProxy (LXC) → Istio NodePort (PROXY v2) → Envoy
```

**HAProxy → Istio:** both HTTP and HTTPS backends use `send-proxy-v2`. PROXY protocol `src` = Cloudflare IP (HAProxy's `allowed_src` ACL already filters to Cloudflare ranges + LAN only, so nothing else can reach the cluster).

**Istio gateway already configured correctly:**
```yaml
proxy.istio.io/config: '{"gatewayTopology":{"proxyProtocol":{},"numTrustedProxies":1}}'
```
- `proxyProtocol: {}` → Envoy reads PROXY protocol, sets downstream = Cloudflare IP
- `numTrustedProxies: 1` → trusts 1 hop, uses XFF to find real client

**What `x_forwarded_for` contains in the access log:**

Cloudflare sets `X-Forwarded-For: <real-client-ip>`. HAProxy HTTP frontend appends Cloudflare IP via `option forwardfor`. Envoy forwards upstream as:

```
x_forwarded_for: "<real-client-ip>, <cloudflare-ip>"
```

**CrowdSec must ban on the leftmost XFF entry** (real client IP), not the rightmost (Cloudflare IP). The `crowdsecurity/istio` parser is designed for this — verify it extracts index `[0]` not `[-1]` from the XFF list before enabling live bans.

**XFF is trustworthy:** HAProxy's `allowed_src` ACL means only Cloudflare can set XFF — no spoofing risk.

---

## Notes

- Validate XFF parsing in non-prod before enabling live bans in prod. A misconfigured ban target would block all Cloudflare traffic.
- CrowdSec free tier includes community blocklists. No account needed, but enrolling at app.crowdsec.net gives a dashboard and premium threat feeds.
- Start with scenarios in log/simulation mode (`--no-api`) to validate parsing before live bans.
- Bouncer API key is external to k8s — goes directly into `home-playbooks` `terraform.tfvars`, no cluster secret needed.
- Non-prod cluster has no HAProxy bouncer — deploy CrowdSec there without NodePort/bouncer for parsing/detection validation only.
