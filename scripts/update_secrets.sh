#!/bin/bash


# Install YQ if its not already
VERSION=v4.44.1
BINARY=yq_linux_amd64
if [ ! -f /usr/bin/yq ]; then
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - | tar xz && sudo mv ${BINARY} /usr/bin/yq
fi

if [ ! -f .env ]; then
  echo ".env file does not exist!"
  exit 1
fi
source .env

# Update cloudflare secret
export SECRET_VALUE=$(echo -n $CLOUDFLARE_TOKEN | kubeseal --raw --scope cluster-wide)
yq -i '.spec.encryptedData.api-token = strenv(SECRET_VALUE)' ./infrastructure/config/cloudflare-secret.yaml

# Update drone secrets
export SECRET_VALUE=$(echo -n $DRONE_RPC_SECRET | kubeseal --raw --scope namespace-wide --namespace drone)
yq -i '.spec.encryptedData.DRONE_RPC_SECRET = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

export SECRET_VALUE=$(echo -n $DRONE_GITHUB_CLIENT_ID | kubeseal --raw --scope namespace-wide --namespace drone)
yq -i '.spec.encryptedData.DRONE_GITHUB_CLIENT_ID = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

export SECRET_VALUE=$(echo -n $DRONE_GITHUB_CLIENT_SECRET | kubeseal --raw --scope namespace-wide --namespace drone)
yq -i '.spec.encryptedData.DRONE_GITHUB_CLIENT_SECRET = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

export SECRET_VALUE=$(echo -n $DRONE_DATABASE_DATASOURCE | kubeseal --raw --scope namespace-wide --namespace drone)
yq -i '.spec.encryptedData.DRONE_DATABASE_DATASOURCE = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

# Update gluetun secrets
export SECRET_VALUE=$(echo -n $OPENVPN_USER | kubeseal --raw --scope namespace-wide --namespace media)
yq -i '.spec.encryptedData.OPENVPN_USER = strenv(SECRET_VALUE)' ./apps/media/gluetun-secrets.yaml

export SECRET_VALUE=$(echo -n $OPENVPN_PASSWORD | kubeseal --raw --scope namespace-wide --namespace media)
yq -i '.spec.encryptedData.OPENVPN_PASSWORD = strenv(SECRET_VALUE)' ./apps/media/gluetun-secrets.yaml

# Update harbor secrets
export SECRET_VALUE=$(echo -n $HARBOR_ADMIN_PASSWORD | kubeseal --raw --scope namespace-wide --namespace harbor)
yq -i '.spec.encryptedData.adminPassword = strenv(SECRET_VALUE)' ./apps/homelab/harbor/harbor-secrets.yaml

export SECRET_VALUE=$(echo -n $HARBOR_POSTGRES_PASSWORD | kubeseal --raw --scope namespace-wide --namespace harbor)
yq -i '.spec.encryptedData.password = strenv(SECRET_VALUE)' ./apps/homelab/harbor/harbor-secrets.yaml

kubectl create secret docker-registry regcred \
  --namespace=harbor \
  --docker-server=harbor.local.example.com \
  --docker-username=$HARBOR_REG_USERNAME \
  --docker-password=$HARBOR_REG_PASSWORD \
  --docker-email=$HARBOR_REG_EMAIL \
  --output json --dry-run=client | kubeseal --scope cluster-wide > ./apps/homelab/harbor/harbor-regcred.json