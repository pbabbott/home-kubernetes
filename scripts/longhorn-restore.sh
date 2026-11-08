#!/usr/bin/env bash
# Restore a Longhorn backup on gen3 into a PVC with the exact name/namespace/size an app expects.
# See docs/ai-reference-gen3-data-move.md for the full per-app runbook.
#
#   Volume CR (fromBackup) -> static PV (Retain, claimRef) -> pre-created PVC (volumeName)
#
# DEFAULT IS DRY-RUN: prints the manifests and validates them. Nothing is created without --apply.
# It never deletes BackupTarget / BackupVolume / Backup CRs (that may delete remote backups).
set -euo pipefail

CTX="prod-gen3"
LH_NS="longhorn-system"
LIVE_URLS=(
  "nfs://192.168.4.124:/volume1/Backups/longhorn-prod"
  "nfs://192.168.4.124:/volume1/Backups/longhorn-nonprod"
)
GEN3_OWN_URL="nfs://192.168.4.124:/volume1/Backups/longhorn-prod-gen3"

usage() {
  cat <<'EOF'
Usage: longhorn-restore.sh --target-url URL --backup-volume pvc-... --backup backup-... \
         --namespace NS --pvc NAME --size 2Gi [options]

Required:
  --target-url URL        Backup store URL, e.g. nfs://192.168.4.124:/volume1/Backups/longhorn-prod.pre-gen3-copy
                          A BackupTarget CR with this URL must already exist on gen3 (this script never creates one).
  --backup-volume NAME    ORIGINAL gen2 Longhorn volume name (pvc-<uuid>), as in the backup URL "volume=" part
  --backup NAME           Backup name (backup-<hex>)
  --namespace NS          Namespace of the PVC the app expects
  --pvc NAME              Name of the PVC the app expects
  --size SIZE             Must equal the PVC request in the app manifest (e.g. 2Gi, 500Mi, 1Ti)

Options:
  --access-mode MODE      PVC access mode (default ReadWriteOnce)
  --storage-class NAME    storageClassName on BOTH PV and PVC (default longhorn; must equal the app manifest)
  --replicas N            Replica count of the restored volume (default 2)
  --context CTX           kubectl context (default prod-gen3; --apply refuses anything else)
  --allow-live-store      Required if --target-url is gen2's LIVE store (longhorn-prod / longhorn-nonprod)
  --apply                 Actually create objects (default: dry-run)
  --wait-timeout SECS     Wait for restore to finish (default 900)
  --verify                After --apply, run a read-only pod listing the PVC contents (file count)
  --cleanup               Delete ONLY the PVC, PV, Volume this script created for --namespace/--pvc
                          (found by label; never touches BackupTarget/BackupVolume/Backup CRs)
  -h, --help
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

TARGET_URL="" BACKUP_VOLUME="" BACKUP="" NS="" PVC="" SIZE="" ACCESS="ReadWriteOnce"
SC="longhorn" REPLICAS=2 APPLY=0 ALLOW_LIVE=0 TIMEOUT=900 VERIFY=0 CLEANUP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-url) TARGET_URL="$2"; shift 2 ;;
    --backup-volume) BACKUP_VOLUME="$2"; shift 2 ;;
    --backup) BACKUP="$2"; shift 2 ;;
    --namespace) NS="$2"; shift 2 ;;
    --pvc) PVC="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --access-mode) ACCESS="$2"; shift 2 ;;
    --storage-class) SC="$2"; shift 2 ;;
    --replicas) REPLICAS="$2"; shift 2 ;;
    --context) CTX="$2"; shift 2 ;;
    --allow-live-store) ALLOW_LIVE=1; shift ;;
    --apply) APPLY=1; shift ;;
    --wait-timeout) TIMEOUT="$2"; shift 2 ;;
    --verify) VERIFY=1; shift ;;
    --cleanup) CLEANUP=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

kc() { kubectl --context "$CTX" "$@"; }
# Pre-created objects use their OWN server-side-apply field manager. If Flux (kustomize-controller) ever owned
# spec.volumeName it would try to remove it on its next apply and fail (bound PVC spec is immutable).
FM="longhorn-restore.sh"
ssa() { kc apply --server-side --field-manager="$FM" -f -; }

[[ -n "$NS" && -n "$PVC" ]] || { usage >&2; die "--namespace and --pvc are required"; }
VOL="restored-${NS}-${PVC}"
LABEL_KEY="longhorn-restore.sh/pvc"
LABEL_VAL="${NS}.${PVC}"
LABEL_VAL="${LABEL_VAL:0:63}"

# ---- cleanup mode -----------------------------------------------------------------------------
if [[ $CLEANUP -eq 1 ]]; then
  [[ "$CTX" == "prod-gen3" ]] || die "refusing cleanup on context '$CTX' (only prod-gen3)"
  echo "Will delete (by label $LABEL_KEY=$LABEL_VAL): PVC $NS/$PVC, PV, Volume $LH_NS/$VOL"
  if [[ $APPLY -eq 0 ]]; then echo "(dry-run; pass --apply to delete)"; exit 0; fi
  kc -n "$NS" delete pvc -l "$LABEL_KEY=$LABEL_VAL" --wait=true
  kc delete pv -l "$LABEL_KEY=$LABEL_VAL" --wait=true
  kc -n "$LH_NS" delete volumes.longhorn.io -l "$LABEL_KEY=$LABEL_VAL" --wait=true
  echo "cleanup done (BackupTarget/BackupVolume/Backup CRs untouched)"
  exit 0
fi

[[ -n "$TARGET_URL" && -n "$BACKUP_VOLUME" && -n "$BACKUP" && -n "$SIZE" ]] \
  || { usage >&2; die "missing required argument"; }
[[ "$BACKUP_VOLUME" =~ ^pvc-[0-9a-f-]+$ ]] || die "--backup-volume must be the original pvc-<uuid> volume name"
[[ "$BACKUP" =~ ^[a-z0-9-]+$ ]] || die "--backup looks wrong: $BACKUP"

# ---- size -> bytes ----------------------------------------------------------------------------
to_bytes() {
  local s="$1" n u
  [[ "$s" =~ ^([0-9]+)(Ki|Mi|Gi|Ti)?$ ]] || die "bad --size '$s' (use e.g. 2Gi)"
  n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]:-}"
  case "$u" in
    "") echo "$n" ;;
    Ki) echo $((n * 1024)) ;;
    Mi) echo $((n * 1024 * 1024)) ;;
    Gi) echo $((n * 1024 * 1024 * 1024)) ;;
    Ti) echo $((n * 1024 * 1024 * 1024 * 1024)) ;;
  esac
}
BYTES="$(to_bytes "$SIZE")"

# ---- safety: live / own store -----------------------------------------------------------------
NORM="${TARGET_URL%%\?*}"; NORM="${NORM%/}"
for live in "${LIVE_URLS[@]}"; do
  if [[ "$NORM" == "$live" ]]; then
    if [[ $ALLOW_LIVE -ne 1 ]]; then
      cat >&2 <<EOF
REFUSING: $NORM is gen2's LIVE Longhorn store.
Restoring from it is only valid in a real data move: gen2 app scaled to 0, a fresh final backup
verified Completed, and the user approved the temporary BackupTarget. Record NAS file count and
newest mtime before and after (docs/ai-reference-gen3-data-move.md). Re-run with --allow-live-store.
EOF
      exit 2
    fi
    echo "!! LIVE STORE ($NORM) allowed by --allow-live-store. Verify the store before/after (read-only check)." >&2
  fi
done
[[ "$NORM" != "$GEN3_OWN_URL" ]] || die "$NORM is gen3's own backup store; restore from the gen2 store/copy instead"

if [[ $APPLY -eq 1 && "$CTX" != "prod-gen3" ]]; then
  die "--apply only allowed on context prod-gen3 (got '$CTX')"
fi

# ---- find BackupTarget with this URL and validate the backup ----------------------------------
TARGET_NAME=""
while read -r name url; do
  u="${url%/}"
  if [[ "$u" == "$NORM" ]]; then TARGET_NAME="$name"; break; fi
done < <(kc -n "$LH_NS" get backuptargets.longhorn.io \
          -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.backupTargetURL}{"\n"}{end}')
[[ -n "$TARGET_NAME" ]] || die "no BackupTarget CR with URL $NORM on $CTX. Create one (ask the user for live paths), pollInterval 0s, then sync."
echo "BackupTarget: $TARGET_NAME"

B_STATE="$(kc -n "$LH_NS" get backups.longhorn.io "$BACKUP" -o jsonpath='{.status.state}' 2>/dev/null || true)"
B_URL="$(kc -n "$LH_NS" get backups.longhorn.io "$BACKUP" -o jsonpath='{.status.url}' 2>/dev/null || true)"
[[ -n "$B_URL" ]] || die "Backup CR '$BACKUP' not found on gen3 (sync target '$TARGET_NAME' first: patch spec.syncRequestedAt)"
[[ "$B_STATE" == "Completed" ]] || die "Backup '$BACKUP' state is '$B_STATE', not Completed"
[[ "$B_URL" == *"volume=$BACKUP_VOLUME"* ]] || die "Backup '$BACKUP' does not belong to volume $BACKUP_VOLUME (url: $B_URL)"
[[ "${B_URL%%\?*}" == "$NORM" ]] || die "Backup '$BACKUP' URL store (${B_URL%%\?*}) differs from --target-url"
echo "Backup: $BACKUP Completed ($B_URL)"

# ---- refuse to overwrite ----------------------------------------------------------------------
kc -n "$LH_NS" get volumes.longhorn.io "$VOL" >/dev/null 2>&1 && die "Volume $VOL already exists"
kc -n "$NS" get pvc "$PVC" >/dev/null 2>&1 && die "PVC $NS/$PVC already exists (pre-create must come first)"
kc get pv "$VOL" >/dev/null 2>&1 && die "PV $VOL already exists"

# ---- manifests --------------------------------------------------------------------------------
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
manifests() {
cat <<EOF
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: $VOL
  namespace: $LH_NS
  labels:
    $LABEL_KEY: "$LABEL_VAL"
  annotations:
    longhorn-restore.sh/run: "$RUN_ID"
    longhorn-restore.sh/source: "$B_URL"
spec:
  size: "$BYTES"
  numberOfReplicas: $REPLICAS
  frontend: blockdev
  fromBackup: "$B_URL"
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $VOL
  labels:
    $LABEL_KEY: "$LABEL_VAL"
spec:
  capacity:
    storage: $SIZE
  volumeMode: Filesystem
  accessModes: [$ACCESS]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $SC
  claimRef:
    namespace: $NS
    name: $PVC
  csi:
    driver: driver.longhorn.io
    fsType: ext4
    volumeHandle: $VOL
    volumeAttributes:
      numberOfReplicas: "$REPLICAS"
      staleReplicaTimeout: "30"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
  namespace: $NS
  labels:
    $LABEL_KEY: "$LABEL_VAL"
spec:
  storageClassName: $SC
  volumeName: $VOL
  accessModes: [$ACCESS]
  resources:
    requests:
      storage: $SIZE
EOF
}

if [[ $APPLY -eq 0 ]]; then
  echo "== DRY-RUN: manifests that --apply would create =="
  manifests
  echo "== server-side validation (--dry-run=server) =="
  # Volume and PV validate without the namespace; PVC needs the namespace to exist.
  manifests | kc apply --server-side --field-manager="$FM" --dry-run=server -f - 2>&1 || echo "(some objects could not be validated, e.g. missing namespace $NS)"
  echo "Dry-run only. Re-run with --apply to create."
  exit 0
fi

kc get ns "$NS" >/dev/null 2>&1 || die "namespace $NS does not exist; create it first"

echo "== applying Volume =="
manifests | awk 'BEGIN{n=0} /^---$/{n++} n==0{print}' | ssa

echo "== waiting up to ${TIMEOUT}s for restore of $VOL =="
deadline=$((SECONDS + TIMEOUT))
while :; do
  req="$(kc -n "$LH_NS" get volumes.longhorn.io "$VOL" -o jsonpath='{.status.restoreRequired}' 2>/dev/null || true)"
  st="$(kc -n "$LH_NS" get volumes.longhorn.io "$VOL" -o jsonpath='{.status.state}' 2>/dev/null || true)"
  rb="$(kc -n "$LH_NS" get volumes.longhorn.io "$VOL" -o jsonpath='{.status.robustness}' 2>/dev/null || true)"
  echo "  state=$st robustness=$rb restoreRequired=$req"
  [[ "$req" == "false" && "$st" == "detached" ]] && break
  (( SECONDS < deadline )) || die "timeout waiting for restore; Volume $VOL left in place (inspect, then --cleanup)"
  sleep 5
done

echo "== applying PV + PVC =="
manifests | awk 'BEGIN{n=0} /^---$/{n++} n>=1{print}' | ssa
kc -n "$NS" wait --for=jsonpath='{.status.phase}'=Bound "pvc/$PVC" --timeout=120s

if [[ $VERIFY -eq 1 ]]; then
  echo "== verify: read-only pod =="
  POD="lh-restore-verify-$$"
  ssa <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
  labels:
    $LABEL_KEY: "$LABEL_VAL"
spec:
  restartPolicy: Never
  containers:
    - name: v
      image: busybox:1.36
      command: ["sh", "-c", "echo files=\$(find /data -type f | wc -l); du -sh /data; ls /data | head -20"]
      volumeMounts:
        - {name: d, mountPath: /data, readOnly: true}
  volumes:
    - name: d
      persistentVolumeClaim: {claimName: $PVC, readOnly: true}
EOF
  kc -n "$NS" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$POD" --timeout=180s || true
  kc -n "$NS" logs "$POD" || true
  kc -n "$NS" delete pod "$POD" --wait=true
fi
echo "Done: PVC $NS/$PVC Bound to restored Volume $VOL (PV reclaim: Retain)."
