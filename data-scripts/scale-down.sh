#!/bin/bash

NAMESPACE="uptime-kuma"
DEPLOY_NAME="uptime-kuma"

echo "scaling deployment down"
kubectl scale deploy -n $NAMESPACE $DEPLOY_NAME --replicas=0