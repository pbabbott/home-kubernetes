if [ -z "$OP_CONNECT_TOKEN" ]; then
  echo "Error: OP_CONNECT_TOKEN environment variable not set!"
  exit 1
fi

mkdir -p ./temp
vaultName=Homelab
itemName=harbor.local.abbottland.io
filepath=./temp/harbor-credentials.json
# TODO: cache this file across runs
op item get $itemName --format json --vault $vaultName > $filepath
HARBOR_REG_USERNAME=$(cat $filepath | jq -r '.fields[] | select(.id == "username") | .value')
HARBOR_REG_PASSWORD=$(cat $filepath | jq -r '.fields[] | select(.id == "password") | .value')
HARBOR_REG_EMAIL=$(cat $filepath | jq -r '.fields[] | select(.label == "email") | .value')

rm $filepath

# Useful for debugging
# echo "HARBOR_REG_USERNAME: $HARBOR_REG_USERNAME"
# echo "HARBOR_REG_PASSWORD: $HARBOR_REG_PASSWORD"
# echo "HARBOR_REG_EMAIL: $HARBOR_REG_EMAIL"
# HARBOR_REGCRED=$(kubectl create secret docker-registry regcred \
#   --docker-server=harbor.local.abbottland.io \
#   --docker-username=$HARBOR_REG_USERNAME \
#   --docker-password=$HARBOR_REG_PASSWORD \
#   --docker-email=$HARBOR_REG_EMAIL \
#   --output json --dry-run=client | jq -r '.data' | jq -r '.".dockerconfigjson"')
# echo "HARBOR_REGCRED: $HARBOR_REGCRED"

create_reg_cred_secret() {
  local targetNamespace=$1
  local targetFile=$2

  kubectl create secret docker-registry regcred \
  --namespace=$targetNamespace \
  --docker-server=harbor.local.abbottland.io \
  --docker-username=$HARBOR_REG_USERNAME \
  --docker-password=$HARBOR_REG_PASSWORD \
  --docker-email=$HARBOR_REG_EMAIL \
  --output json --dry-run=client \
  | kubeseal \
    --scope namespace-wide \
    --namespace $targetNamespace \
    | yq --prettyPrint > $targetFile
}

# Update registry credentials throughout the cluster
create_reg_cred_secret media ./apps/media/harbor-regcred.yaml
create_reg_cred_secret flux-system ./clusters/homelab/harbor-regcred.yaml
create_reg_cred_secret brandon-dev ./apps/homelab/development/harbor-regcred.yaml
create_reg_cred_secret home-hud ./apps/homelab/home-hud/harbor-regcred.yaml

