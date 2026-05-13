# Session: ARC Runner listenerTemplate Fix

**Date:** 2026-05-13  
**Cluster:** nonprod-gen2

## Problem

Two HelmReleases failing, blocking `kustomization/apps-ks`:

- `arc-runner-amd64` — `AutoscalingRunnerSet "non-prod-gen2-amd64-runner" is invalid: spec.listenerTemplate.spec.containers: Required value`
- `arc-runner-dind-amd64` — same error

## Root Cause

ARC chart v0.14.1 CRD (`AutoscalingRunnerSet`) requires `spec.listenerTemplate.spec.containers` to be present. Both HelmReleases only had `dnsConfig` under `listenerTemplate.spec`, no `containers` field.

## Fix

Added `containers: [{name: listener}]` to `listenerTemplate.spec` in both files:

- `applications/base/arc/arc-runner-amd64-helmrelease.yaml`
- `applications/base/arc/arc-runner-dind-amd64-helmrelease.yaml`

Chart fills in image/command from defaults; only the container name is required to satisfy CRD validation.

## Outcome

Commit `c6f263e` pushed. Flux reconciled `apps-ks`. Both HelmReleases now `Ready: True`.
