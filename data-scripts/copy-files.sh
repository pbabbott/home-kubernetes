#!/bin/bash

NAMESPACE="uptime-kuma"
LOCAL="./temp/kuma-files/."
REMOTE="pvc-both:/mnt/data"

mkdir -p $LOCAL

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <upload|download>"
  exit 1
fi

DIRECTION=$1

if [ "$DIRECTION" == "upload" ]; then
  kubectl -n $NAMESPACE cp $LOCAL $REMOTE
elif [ "$DIRECTION" == "download" ]; then
  kubectl -n $NAMESPACE cp $REMOTE $LOCAL
else
  echo "Invalid argument: $DIRECTION. Use 'upload' or 'download'."
  exit 1
fi