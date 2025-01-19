if [ -z "$OP_CONNECT_TOKEN" ]; then
  echo "Error: OP_CONNECT_TOKEN environment variable not set!"
  exit 1
fi

if [ ! -f "./1password-credentials.json" ]; then
  echo "Error: 1password-credentials.json file not found!"
  exit 1
fi

mkdir -p ./temp

# op-connect expects content of this secret to be base64 encoded
# the -w 0 flag is used to prevent line breaks
# https://github.com/1Password/connect/issues/62#issuecomment-2065447121
base64 -w 0 < ./1password-credentials.json > ./temp/1password-credentials.json.base64

kubectl create secret generic op-credentials \
    --namespace=op-connect \
    --from-file=1password-credentials.json=./temp/1password-credentials.json.base64 \
    --output json --dry-run=client > ./temp/op-connect-secret.yaml

kubeseal \
  --scope namespace-wide \
  --namespace op-connect \
  < ./temp/op-connect-secret.yaml \
  | yq --prettyPrint > ./infrastructure/controllers/1password/op-credentials.yaml

export SECRET_VALUE=$(echo -n $OP_CONNECT_TOKEN | kubeseal --raw --scope namespace-wide --namespace op-connect)
yq -i '.spec.encryptedData.token = strenv(SECRET_VALUE)' ./infrastructure/controllers/1password/op-credentials.yaml

rm ./temp/1password-credentials.json.base64