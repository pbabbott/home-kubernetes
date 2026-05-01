#!/usr/bin/env bash
# Outputs a Grafana service account token to stdout.
#
# Examples:
#   export GRAFANA_TOKEN_NON_PROD=$(./scripts/get-grafana-api-key.sh)
#   export GRAFANA_TOKEN_PROD=$(KUBE_CONTEXT=prod-gen2 ./scripts/get-grafana-api-key.sh)
set -euo pipefail

CONTEXT="${KUBE_CONTEXT:-nonprod-gen2}"
NAMESPACE="kube-prometheus-stack"
SECRET_NAME="kube-prometheus-stack-grafana"
SA_NAME="${GRAFANA_SA_NAME:-automation}"
GRAFANA_PORT=3000
GRAFANA_SVC="kube-prometheus-stack-grafana"

# Retrieve admin credentials from cluster secret
ADMIN_USER=$(kubectl --context "$CONTEXT" get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.admin-user}' | base64 -d)
ADMIN_PASS=$(kubectl --context "$CONTEXT" get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.admin-password}' | base64 -d)

# Port-forward Grafana in background
kubectl --context "$CONTEXT" port-forward -n "$NAMESPACE" \
  "svc/$GRAFANA_SVC" "$GRAFANA_PORT:80" &>/dev/null &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null' EXIT

# Wait for port-forward to be ready
for i in $(seq 1 10); do
  curl -s "http://localhost:$GRAFANA_PORT/api/health" &>/dev/null && break
  sleep 1
done

BASE_URL="http://localhost:$GRAFANA_PORT"
AUTH="-u ${ADMIN_USER}:${ADMIN_PASS}"

# Create service account (idempotent — ignore conflict)
SA_RESPONSE=$(curl -sf $AUTH -X POST "$BASE_URL/api/serviceaccounts" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$SA_NAME\", \"role\": \"Admin\"}" 2>/dev/null || true)

# If SA already exists, fetch its id by name
SA_ID=$(echo "$SA_RESPONSE" | jq -r '.id // empty')
if [ -z "$SA_ID" ]; then
  SA_ID=$(curl -sf $AUTH "$BASE_URL/api/serviceaccounts/search?query=$SA_NAME" \
    | jq -r ".serviceAccounts[] | select(.name == \"$SA_NAME\") | .id")
fi

if [ -z "$SA_ID" ]; then
  echo "Error: could not create or find service account '$SA_NAME'" >&2
  exit 1
fi

# Generate token
TOKEN_NAME="${SA_NAME}-$(date +%Y%m%d%H%M%S)"
TOKEN_RESPONSE=$(curl -sf $AUTH -X POST "$BASE_URL/api/serviceaccounts/$SA_ID/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$TOKEN_NAME\"}")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.key')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Error: failed to retrieve token from response" >&2
  echo "$TOKEN_RESPONSE" >&2
  exit 1
fi

echo "$TOKEN"
