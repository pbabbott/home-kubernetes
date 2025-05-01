#
- go to longhorn ui
- create a volume via UI

    - name: dashy-item-icons-pv
    - size 100Mi
    - replicas 3
    - frontend block device
    - data lcality


- create pv

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: longhorn-static-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain  # Prevent deletion when PVC is removed
  storageClassName: longhorn
  csi:
    driver: driver.longhorn.io
    fsType: ext4
    volumeHandle: longhorn-static-pv  # Must match the Longhorn volume name

```

- create pvc

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-static-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  volumeName: longhorn-static-pv  # Bind to the PV
  storageClassName: ""  # Must be empty for static binding
```

in event of crash

create pv (not from ui, but from charts)

```sh
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: longhorn-static-pv  # Same name as original PV
  namespace: longhorn-system
spec:
  fromBackup: s3://your-backup-path  # Use the backup URL from Longhorn

```