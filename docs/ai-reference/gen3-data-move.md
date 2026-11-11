# Gen2 → gen3 per-app data move (runbook)

Volume-by-volume decisions: `docs/plans/2026-11-08-gen2-to-gen3-migration.md` (Appendix B).
Helper: `scripts/longhorn-restore.sh` (dry-run by default). Contexts: `kubectl --context prod-gen2|prod-gen3`.
An app runs in ONE cluster at a time (shared NAS Postgres/Redis/NFS).

## Ground rules
- Never write to `longhorn-prod` (live), `longhorn-prod.pre-gen3-copy`, `longhorn-nonprod*`. Gen3 backs up only to `longhorn-prod-gen3`. TRAP: a restored Volume inherits `spec.backupTargetName: live-restore`, so its recurring backups go to `longhorn-prod` until you patch it to `default` (done for all 8 on 2026-11-11, first backups verified `Completed` in `longhorn-prod-gen3`).
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

## Known gaps / loose ends (2026-11-08) — read if data looks wrong in a later phase
Status legend: TESTED = done in a scratch run; UNTESTED = reasoned only.

### What was never exercised
- TESTED 2026-11-09 for harbor (trivy StatefulSet PVC and `harbor-jobservice` adopted the pre-created PVCs; see "Phase 7 harbor learnings"). Still UNTESTED for actions-cache. Original note: chart/controller-created PVCs (`data-harbor-trivy-0` from the StatefulSet template, `harbor-jobservice`, actions-cache). Only a Flux-managed PVC (`prowlarr-config`) was tested. Assumption: a StatefulSet/chart adopts an existing PVC with the exact name; verify `kubectl describe pvc`/pod events right after enabling. Note a StatefulSet PVC keeps the label/selector of its template; mismatched `storageClassName`/size in the chart values vs the pre-created PVC will block the pod.
- TESTED 2026-11-09: `harbor-registry-nas` rsync (264.2 GB, ~35 min warm pre-copy), the provisioner dir name `prod-gen3/harbor-harbor-registry-nas` (as assumed). TRAP: rsync as a non-root user leaves the files owned by that user; the registry (uid 10000) then cannot write. chown them to 10000:10000 (root Job in the PVC, or rsync as root). The static-NFS-PV fallback stayed UNTESTED (not needed).
- UNTESTED: RWX Longhorn volumes (none exist); only RWO restores were done. Media/home-hud NFS PVs were not re-created on gen3.
- UNTESTED: volumes bigger than 2Gi (largest to restore is 10Gi `openclaw-pvc`); restore of a backup taken from a volume in use by the app (final backups are taken with the app at 0 in a real move; the dry-run backup was taken from a RUNNING prowlarr, so it is crash-consistent only).
- UNTESTED: whether the restored app actually STARTS and is happy with the data (file ownership/permissions, config DB version, app-level schema). The dry-run only listed files with a busybox pod running as root. If an app can't write its config dir, check `fsGroup`/`runAsUser` in the deployment and `ls -ln` of the mount.

### Traps that can look like "missing/old data"
- gen3 only learns about new gen2 backups on a BackupTarget **sync** (`pollInterval: 0s`). After the final gen2 backup, patch `spec.syncRequestedAt` on the target (`live-restore`) and confirm the Backup CR exists and is `Completed` BEFORE running the script. The script fails if the CR is missing, but a stale-but-present older backup will happily restore: check `--backup` is the final one (compare `status.snapshotCreatedAt` to the scale-to-0 time).
- Retention: gen2 `daily-backups` keeps 7. A manual backup with a custom name (like `data-move-final-prowlarr`) was not observed being pruned, but that is UNVERIFIED. Record the final backup name and restore soon; do not rely on it existing in a week.
- Backups of the same volume keep running on gen2 at 03:00 UTC while the app is at 0 (detached volume), producing unchanged-data backups. Harmless, but "latest backup" may then be a recurring one, not your final one; both contain the same data if the app was at 0 before the final backup.
- Stale backups to ignore: `coder-workspaces` home (last 2026-07-23) and the old Longhorn `arc-pnpm-store` BackupVolume (last 2026-07-25). Neither volume is restored (start empty).
- A restored `Volume` has a different name from the gen2 PV (`restored-<ns>-<pvc>`); the original `pvc-<uuid>` is only used in the `volume=` part of `fromBackup`. Searching for the gen2 name on gen3 finds nothing.
- PV is `Retain`: deleting the gen3 PVC leaves PV `Released` with a stale claimRef uid; it cannot rebind. Use `longhorn-restore.sh --cleanup --apply` (labels), then restore again; do not delete the Volume CR by hand unless you mean it.
- gen2 volumes are reclaim `Delete`: once the gen2 PVC is deleted the live volume is gone. Until then gen2 is the rollback.
- Flux and the pre-created PVC: if Flux's apply fails with "spec is immutable", `kustomize-controller` has probably taken ownership of `volumeName` (PVC was created by plain `kubectl apply`/Helm). Fix: delete the PVC (and PV claimRef) and recreate with the script (own field manager). Mismatch in `storageClassName`, `accessModes` or a smaller size is also rejected.
- Scratch/test remnants: none left on gen3. All leftovers were deleted 2026-11-11 (issue #40): BackupTargets `rehearsal-copy`/`live-restore`, Backups `data-move-final-prowlarr`/`p7-final-*`, and the NAS dirs `longhorn-prod` and `longhorn-prod.pre-gen3-copy`. This runbook is now history. Deleting a Backup/BackupTarget CR may delete remote data (unverified), so do not clean up leftovers casually.

### Shared-state hazards (not Longhorn) when apps come online
- NAS Postgres/Redis/NFS are shared by gen2 and gen3. If an app's data looks odd, first confirm the gen2 copy is really at 0 (`kubectl --context prod-gen2 get pods -A | grep <app>`) and its Flux object is suspended/removed, or gen2 will keep writing.
- Harbor: registry blobs (NAS dir) must match the Postgres metadata. Copying the dir while gen2 Harbor ran can leave dangling blobs or missing layers; redo the rsync at scale-0 and run Harbor garbage collection only after verifying pushes/pulls.
- Media: `media-pv` and `home-hud-media-pv` both point at `/volume1/Media`; two apps on two clusters writing the same tree is the main way to corrupt media state.
- Sonarr/radarr/qbit configs restored from the final backup embed gen2-era paths/URLs/API keys. Prowlarr→sonarr/radarr links and the qbit download client use in-cluster service names; they should be unchanged but confirm after start. gluetun needs working VPN from the gen3 node network (not tested).

### Evidence to compare against (live store, 2026-11-08 17:16 UTC)
`longhorn-prod` 46,872 files / 43,552 dirs (after the one test backup; before 46,853 / 43,531), `longhorn-prod.pre-gen3-copy` 47,999 / 44,425, `longhorn-prod-gen3` 0 files. prowlarr-config restore = 692 files, 90.1M. Counts will legitimately grow after gen2's daily 03:00 UTC job.

