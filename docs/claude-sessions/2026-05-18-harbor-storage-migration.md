# 2026-05-18 Harbor Storage Migration

## Problem
Harbor registry pod (`harbor` namespace, prod-gen2) had `/storage` volume (Longhorn PVC `harbor-registry`, 5Gi) full at 4.8G/4.8G. All image pushes failing with 500 errors. Harbor-core logs showed `http: proxy error: context canceled` on blob write attempts.

## What We Did

### 1. Emergency PVC Resize (Longhorn)
- Patched `harbor-registry` PVC from 5Gi → 50Gi via `kubectl patch pvc`
- Restarted `harbor-registry` deployment to complete filesystem resize
- Result: 44G free, service restored
- Updated HelmRelease base to `size: 50Gi`

### 2. NFS Provisioner Deployment (both gen2 clusters)
- Ported gen1 `nfs-subdir-external-provisioner` pattern to gen2 infra
- Created `infra/base/nas-storage/` with chart `nfs-subdir-external-provisioner` v4.0.18
- NFS server: `192.168.4.124`, base path: `/volume1/ClusterStorage`
- Created cluster-specific overlays patching NFS path:
  - `infra/prod-gen2/nas-storage/` → `/volume1/ClusterStorage/prod-gen2`
  - `infra/non-prod-gen2/nas-storage/` → `/volume1/ClusterStorage/non-prod-gen2`
- StorageClass name: `nas-storage` (non-default), `archiveOnDelete: true`
- Fix required: HelmRepository API was `v1beta2` (gen1) → changed to `v1` (gen2 requirement)

### 3. Harbor Registry Migration to NFS
- Created `harbor-registry-nas` PVC (200Gi, `nas-storage` StorageClass) in `harbor` namespace
- Suspended harbor HelmRelease, scaled registry to 0
- Migration pod (alpine + rsync) copied 5.9GB from `harbor-registry` → `harbor-registry-nas`
- Updated HelmRelease: replaced `storageClass: longhorn` + `size: 50Gi` with `existingClaim: harbor-registry-nas`
- Resumed HelmRelease, Flux reconciled, deployment rolled out
- Verified `/storage` now mounted from `192.168.4.124:/volume1/ClusterStorage/prod-gen2/harbor-harbor-registry-nas` (22TB available)
- Deleted old `harbor-registry` Longhorn PVC (50Gi returned to Longhorn pool)

## Commits
- `fix(harbor): increase registry PVC size to 50Gi`
- `feat(infra): add nfs-subdir-external-provisioner to gen2 clusters`
- `fix(nas-storage): use source.toolkit.fluxcd.io/v1 for HelmRepository`
- `feat(harbor): migrate registry storage to NAS-backed NFS PVC`

## Key Files Changed
- `applications/base/harbor/helmrelease.yaml` — registry now uses `existingClaim: harbor-registry-nas`
- `infra/base/nas-storage/` — new base for NFS provisioner
- `infra/prod-gen2/nas-storage/kustomization.yaml`
- `infra/non-prod-gen2/nas-storage/kustomization.yaml`
- `infra/prod-gen2/kustomization.yaml` + `infra/non-prod-gen2/kustomization.yaml` — wired in `./nas-storage`

## Notes
- `nas-storage` StorageClass is now available on both gen2 clusters for future use
- NFS performance is acceptable for registry blob ops (sequential large reads/writes)
- `data-harbor-trivy-0` and `harbor-jobservice` PVCs still on Longhorn — no issue there (small, infrequent writes)
- `storage-issue.md` in repo root can be deleted
