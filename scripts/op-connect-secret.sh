if [ -z "$OP_CONNECT_TOKEN" ]; then
  echo "Error: OP_CONNECT_TOKEN environment variable not set!"
  exit 1
fi

if [ ! -f "./1password-credentials.json" ]; then
  echo "Error: 1password-credentials.json file not found!"
  exit 1
fi

kubectl create secret generic op-credentials \
    --namespace=op-connect \
    --from-file=1password-credentials.json=./1password-credentials.json \
    --output json --dry-run=client > ./temp/op-connect-secret.yaml

kubeseal \
  --scope namespace-wide \
  --namespace op-connect \
  < ./temp/op-connect-secret.yaml \
  | yq --prettyPrint > ./infrastructure/controllers/1password/op-credentials.yaml

export SECRET_VALUE=$(echo -n $OP_CONNECT_TOKEN | kubeseal --raw --scope namespace-wide --namespace op-connect)
yq -i '.spec.encryptedData.token = strenv(SECRET_VALUE)' ./infrastructure/controllers/1password/op-credentials.yaml
