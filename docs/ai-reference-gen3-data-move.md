# Gen2 → gen3 per-app data move (runbook)

Volume-by-volume decisions: `docs/plans/2026-11-08-gen2-to-gen3-migration.md` (Appendix B).
Helper: `scripts/longhorn-restore.sh` (dry-run by default). Contexts: `kubectl --context prod-gen2|prod-gen3`.
An app runs in ONE cluster at a time (shared NAS Postgres/Redis/NFS).

## Ground rules
- Never write to `longhorn-prod` (live), `longhorn-prod.pre-gen3-copy`, `longhorn-nonprod*`. Gen3 backs up only to `longhorn-prod-gen3`.
- Never delete a `BackupTarget`, `BackupVolume` or `Backup` CR that points at a store you want to keep (may delete remote data, unverified). Leave temp targets idle (`pollInterval: 0s`), like `rehearsal-copy`.
- **Ask the user** before: any gen2 backup, creating a BackupTarget on the live path, any NAS change, any merge.
- Longhorn `Backup` CRs made by hand need the `backup-volume` label.

## Restore from the LIVE store (real move only)
1. gen2 app scaled to 0, user approves a fresh final backup, `Backup` shows `Completed` on gen2.
2. NAS baseline (BusyBox, no `find -printf`): over `ssh pabbott@192.168.4.124`, for `p=/volume1/Backups/longhorn-prod`:
   `find $p -type f | wc -l`; `find $p -type d | wc -l`; `find $p -type f -exec stat -c '%Y %n' {} + | sort -n | tail -1`; `find $p -type f -mmin -30 | wc -l`.
   Do it outside gen2's 03:00-03:10 UTC recurring job (or expect only that job's new files).
3. User approves, then create a temp target on gen3 (idle, never a RecurringJob/volume target):
   ```yaml
   apiVersion: longhorn.io/v1beta2
   kind: BackupTarget
   metadata: {name: live-restore, namespace: longhorn-system}
   spec: {backupTargetURL: "nfs://192.168.4.124:/volume1/Backups/longhorn-prod", credentialSecret: cifs-secret, pollInterval: 0s}
   ```
   then `kubectl --context prod-gen3 -n longhorn-system patch backuptarget live-restore --type merge -p '{"spec":{"syncRequestedAt":"<now UTC RFC3339>"}}'`.
4. Re-run the NAS check after the sync and after the restore; counts and newest mtime must match (aside from the final backup you made).
5. Restore: `scripts/longhorn-restore.sh --allow-live-store ...` (dry-run first). Leave `live-restore` idle afterwards (do not delete it). Verified 2026-11-08: sync + restore left the live store byte-for-byte unchanged apart from the one new backup.
6. Manual gen2 backup (needs user OK): Snapshot CR (`spec: {volume: pvc-…, createSnapshot: true}`), then Backup CR with labels `backup-volume=pvc-…`, `backup-target=default`, `spec.snapshotName: <snapshot>`; wait `status.state=Completed`.

## Per-app procedure with rollback
| # | Step | Rollback |
|---|---|---|
| 0 | Preflight: `flux get ks -A`/`hr -A` healthy on gen3, Longhorn nodes Ready, user OK | n/a |
| 1 | Suspend the app's Flux objects on gen2 (or remove it from the gen2 overlay on a branch), then scale to 0 | resume + scale back up |
| 2 | Ask, then take a final backup of each restore-volume on gen2; verify `Backup` `Completed`; note backup name | none needed (extra backup is harmless) |
| 3 | Create the namespace on gen3 (Flux adopts it later) | delete namespace |
| 4 | Restore with `longhorn-restore.sh --target-url ... --backup-volume pvc-... --backup backup-... --namespace ... --pvc ... --size ... [--allow-live-store] --apply --verify` | `--cleanup --apply` (deletes only PVC, PV, restored Volume) |
| 5 | NFS data (harbor registry): rsync on the NAS into the gen3 provisioner dir, see Appendix B | delete the gen3 dir; gen2 dir untouched |
| 6 | Enable app in gen3 overlay (branch, merge on approval); wait for HR/Kustomization Ready | revert commit |
| 7 | Verify: pods Ready, data present, `flux get ks -A`, `flux get hr -A` on prod-gen3; DNS only after Phase 5 | revert step 6, resume gen2 |
| 8 | Soak, then delete from gen2. PVs there are reclaim `Delete`, so deleting the PVC deletes the volume (backups stay) | restore the final backup onto gen2 |

## PVC binding rules (tested 2026-11-08)
- The script creates: Volume CR (`fromBackup`) → static PV (`Retain`, `claimRef` → target PVC, `storageClassName` = app's, default `longhorn`) → PVC with `volumeName`. Name/namespace/size/accessModes/class must equal the app manifest.
- Use `storageClassName: longhorn` on PV and PVC (not `longhorn-static`): a class mismatch makes Flux's apply fail because a bound PVC's spec is immutable.
- **Field manager matters:** pre-create with its own server-side-apply manager (the script does: `longhorn-restore.sh`). If the PVC is created with `kubectl apply` (client-side) and Flux's server-side apply then adopts it, `kustomize-controller` takes ownership of `volumeName` and the next apply tries to blank it → "spec is immutable" error. With a separate manager Flux's apply is `serverside-applied` and idempotent; Flux does not own `volumeName`.
- Flux apply over the pre-created PVC: same manifest OK; larger request accepted (triggers expansion); smaller request, other storageClass or other accessModes rejected.
- PV is `Retain` during the move so a stray PVC delete cannot delete the restored volume. After the app is stable, decide whether to leave it.
- Chart-created PVCs (harbor `harbor-jobservice`, StatefulSet `data-harbor-trivy-0`, actions-cache): pre-create by exact name BEFORE enabling the app so the controller finds it. Not scratch-tested, only reasoned (a StatefulSet adopts an existing PVC with the template name).
- `restoreRequired=false` + `state=detached` marks the finished restore; `prowlarr-config` (2Gi) took about 30 s.

## Start-empty volumes
arc-runners caches (`turbo-cache-storage`, `actions-cache-server-data`, `arc-pnpm-store`), Prometheus, coder workspace home: let the app create them; do not restore.
