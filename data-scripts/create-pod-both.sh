#!/bin/bash


NAMESPACE="uptime-kuma"
NEW_PVC_NAME="uptime-kuma-app-data-static"
OLD_PVC_NAME="uptime-kuma-app-data"

echo "Creating a temporary pod ..."
kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pvc-both
spec:
  containers:
  - name: rsync
    image: alpine
    command: ["/bin/sh", "-c", "sleep infinity"]
    volumeMounts:
    - mountPath: "/mnt/data"
      name: new-pvc
    - mountPath: "/mnt/old"
      name: old-pvc
  restartPolicy: Never
  volumes:
  - name: new-pvc
    persistentVolumeClaim:
      claimName: $NEW_PVC_NAME
  - name: old-pvc
    persistentVolumeClaim:
      claimName: $OLD_PVC_NAME
EOF