
if [ ! -f "./1password-credentials.json" ]; then
  echo "Error: 1password-credentials.json file not found!"
  exit 1
fi

kubectl create secret generic op-credentials \
    --namespace=op-connect \
    --from-file=1password-credentials.json=./1password-credentials.json \
    --output json --dry-run=client \
    | kubeseal \
      --scope namespace-wide \
      | yq --prettyPrint > ./infrastructure/controllers/op-connect/op-credentials.yaml
