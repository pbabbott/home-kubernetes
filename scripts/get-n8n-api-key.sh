#!/usr/bin/env bash
# Outputs the n8n API key to stdout by retrieving it from 1Password via op-connect.
#
# Examples:
#   export N8N_API_KEY=$(./scripts/get-n8n-api-key.sh)
#   export N8N_API_KEY=$(KUBE_CONTEXT=prod-gen2 ./scripts/get-n8n-api-key.sh)
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-prod-gen2}"
OP_NAMESPACE="op-connect"
OP_PORT=18080
VAULT_ID="fkkvro6akbbm2po5qvh6iask2a"
ITEM_ID="upm27tgw2hpka7ec6uicpkrzqi"
FIELD_LABEL="api-key"

# Port-forward op-connect in background
kubectl --context "$CONTEXT" port-forward -n "$OP_NAMESPACE" \
  svc/onepassword-connect "$OP_PORT:8080" &>/dev/null &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null' EXIT

# Wait for port-forward
for i in $(seq 1 10); do
  curl -s "http://localhost:$OP_PORT/v1/heartbeat" &>/dev/null && break
  sleep 1
done

OP_TOKEN=$(kubectl --context "$CONTEXT" get secret -n "$OP_NAMESPACE" op-credentials \
  -o jsonpath='{.data.token}' | base64 -d)

API_KEY=$(curl -sf -H "Authorization: Bearer $OP_TOKEN" \
  "http://localhost:$OP_PORT/v1/vaults/$VAULT_ID/items/$ITEM_ID" \
  | jq -r ".fields[] | select(.label == \"$FIELD_LABEL\") | .value")

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
  echo "Error: could not retrieve n8n API key from 1Password" >&2
  exit 1
fi

echo "$API_KEY"
