# 2026-05-04 — ARC Runners Debugging

## Goal
Get GitHub Actions self-hosted runners working on non-prod gen2 cluster. Jobs were stuck in queue with no runners picking them up.

## What We Found & Fixed

### 1. Expired GitHub PAT (from prior session)
- `arc-gh-secret` in `arc-runners` namespace had a stale token
- Root cause chain: 1Password Connect Server cached old token; operator read from cache
- Fix: restart Connect Server → delete stale secret → annotate `OnePasswordItem` to force re-sync
- New token (`ghp_QllA...`) synced from 1Password

### 2. `runs-on` label mismatch
- Workflow used `runs-on: [self-hosted, non-prod-gen2-amd64-runner]`
- ARC scale sets require `runs-on: non-prod-gen2-amd64-runner` (scale set name only, no `self-hosted`)
- Evidence: listener showed `"assigned job"=0` continuously — GitHub not routing jobs to the scale set
- Fix: change workflow in `home-web-apps` to `runs-on: non-prod-gen2-amd64-runner`

### 3. DNS wildcard trap (root cause of jobs still stuck after fix #2)
- After routing fix, listener received jobs (`"assigned job"=2`) and scaled runner pods
- Runner pods started but immediately failed: `POST https://broker.actions.githubusercontent.com/session — SSL EOF`
- Traced to DNS: `broker.actions.githubusercontent.com` has 3 dots; with `ndots:5` (K8s default), pod resolver tries search domains first
- Search domain `local.abbottland.io` (from node's systemd-resolved, propagated to pod resolv.conf) expanded the query to `broker.actions.githubusercontent.com.local.abbottland.io`
- Wildcard `*.local.abbottland.io → 192.168.6.28` (HAProxy) caught the query
- HAProxy got the TLS handshake for an unknown domain → dropped connection → SSL EOF in runner
- Go-based listener (on worker-2) avoided this likely due to established long-lived HTTP/2 connection caching the real IP
- Fix: add `ndots: 2` to runner pod `dnsConfig` so 3-dot names resolve absolutely, bypassing search domains

## Files Changed
- `applications/base/arc/arc-runner-amd64-helmrelease.yaml` — added `dnsConfig.options[ndots=2]`
- `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml` — same

## Commit
`c74787b` — fix(arc): set ndots=2 on runner pods to avoid wildcard DNS trap

## Infrastructure Context
- HAProxy at `192.168.6.28` fronts both gen2 clusters
- Split-horizon DNS: `*.local.abbottland.io` wildcard A record → `192.168.6.28`
- Node `/etc/resolv.conf` has `search local.abbottland.io`; this leaks into pod resolv.conf
- Listener pods (`arc-systems` namespace) are Go-based distroless; runner pods are .NET on Ubuntu 24.04
- ARC scale set listener polls `broker.actions.githubusercontent.com/scalesets/message`; runners POST to `broker.actions.githubusercontent.com/session`

## Status at Session End
- Fix committed and pushed; Flux reconcile pending
- Once HelmRelease reconciles, existing runner pods will be replaced with new ones having `ndots:2`
- Validation: watch `kubectl logs -n arc-runners <new-runner-pod>` for successful session creation
