#!/usr/bin/env bash
if [ -f "./.env" ]; then
  set -a
  # shellcheck source=.env
  source ./.env
  set +a
fi

CREDENTIALS_FILE="${OP_CONNECT_CREDENTIALS_FILE:-./1password-credentials.json}"
if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "Error: credentials file not found: $CREDENTIALS_FILE"
  exit 1
fi

# Infer token from credentials filename; fall back to OP_CONNECT_TOKEN
case "$CREDENTIALS_FILE" in
  *nonprod*) TOKEN="${OP_CONNECT_TOKEN_NONPROD:-$OP_CONNECT_TOKEN}" ;;
  *prod*)    TOKEN="${OP_CONNECT_TOKEN_PROD:-$OP_CONNECT_TOKEN}" ;;
  *)         TOKEN="$OP_CONNECT_TOKEN" ;;
esac

if [ -z "$TOKEN" ]; then
  echo "Error: no token found — set OP_CONNECT_TOKEN_NONPROD / OP_CONNECT_TOKEN_PROD in .env"
  exit 1
fi

# SealedSecrets are encrypted for the cluster whose sealed-secrets controller
# kubeseal talks to (default: current kubectl context). Override the output
# path when sealing for another cluster, e.g. non-prod-gen2:
#   OP_CONNECT_CREDENTIALS_FILE=./1password-credentials-nonprod.json OP_CONNECT_SEALED_SECRET_OUTPUT=./infra/non-prod-gen2/onepassword/op-credentials.yaml ./scripts/op-connect-secret.sh
OUTPUT="${OP_CONNECT_SEALED_SECRET_OUTPUT:-./infrastructure/controllers/1password/op-credentials.yaml}"
mkdir -p "$(dirname "$OUTPUT")"
mkdir -p ./temp

# op-connect expects content of this secret to be base64 encoded
# the -w 0 flag is used to prevent line breaks
# https://github.com/1Password/connect/issues/62#issuecomment-2065447121
base64 -w 0 < "$CREDENTIALS_FILE" > ./temp/1password-credentials.json.base64

kubectl create secret generic op-credentials \
    --namespace=op-connect \
    --from-file=1password-credentials.json=./temp/1password-credentials.json.base64 \
    --output json --dry-run=client > ./temp/op-connect-secret.yaml

kubeseal \
  --scope namespace-wide \
  --namespace op-connect \
  < ./temp/op-connect-secret.yaml \
  | yq --prettyPrint > "$OUTPUT"

export SECRET_VALUE=$(echo -n "$TOKEN" | kubeseal --raw --scope namespace-wide --namespace op-connect)
yq -i '.spec.encryptedData.token = strenv(SECRET_VALUE)' "$OUTPUT"

rm ./temp/1password-credentials.json.base64
