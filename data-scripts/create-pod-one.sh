#!/bin/bash


NAMESPACE="uptime-kuma"
TARGET_PVC_NAME="dashy-item-icons-static"

echo "Creating a temporary pod ..."
kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pvc-one
spec:
  containers:
  - name: rsync
    image: alpine
    command: ["/bin/sh", "-c", "sleep infinity"]
    volumeMounts:
    - mountPath: "/mnt/data"
      name: target-pvc
  restartPolicy: Never
  volumes:
  - name: target-pvc
    persistentVolumeClaim:
      claimName: $TARGET_PVC_NAME
EOF