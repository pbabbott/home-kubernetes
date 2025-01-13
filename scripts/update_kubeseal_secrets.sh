#!/bin/bash

# Install YQ if its not already
VERSION=v4.44.1
BINARY=yq_linux_amd64

# TODO: install yq in devcontainer
if [ ! -f /usr/bin/yq ]; then
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - | tar xz && sudo mv ${BINARY} /usr/bin/yq
fi

if [ ! -f .env ]; then
  echo ".env file does not exist!"
  exit 1
fi
source .env


update_cloudflare_secrets() {
  # export SECRET_VALUE=$(echo -n $CLOUDFLARE_TOKEN | kubeseal --raw --scope cluster-wide)
  # yq -i '.spec.encryptedData.api-token = strenv(SECRET_VALUE)' ./infrastructure/controllers/cert-manager/cert-manager-cloudflare-secret.yaml

  export SECRET_VALUE=$(echo -n $CLOUDFLARE_TOKEN | kubeseal --raw --scope namespace-wide --namespace external-dns)
  yq -i '.spec.encryptedData.api-token = strenv(SECRET_VALUE)' ./infrastructure/controllers/external-dns/external-dns-cloudflare-secret.yaml

  export SECRET_VALUE=$(echo -n $CLOUDFLARE_EMAIL | kubeseal --raw --scope namespace-wide --namespace external-dns)
  yq -i '.spec.encryptedData.api-email = strenv(SECRET_VALUE)' ./infrastructure/controllers/external-dns/external-dns-cloudflare-secret.yaml
}

update_drone_secrets() {
  export SECRET_VALUE=$(echo -n $DRONE_RPC_SECRET | kubeseal --raw --scope namespace-wide --namespace drone)
  yq -i '.spec.encryptedData.DRONE_RPC_SECRET = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

  export SECRET_VALUE=$(echo -n $DRONE_GITHUB_CLIENT_ID | kubeseal --raw --scope namespace-wide --namespace drone)
  yq -i '.spec.encryptedData.DRONE_GITHUB_CLIENT_ID = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

  export SECRET_VALUE=$(echo -n $DRONE_GITHUB_CLIENT_SECRET | kubeseal --raw --scope namespace-wide --namespace drone)
  yq -i '.spec.encryptedData.DRONE_GITHUB_CLIENT_SECRET = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml

  export SECRET_VALUE=$(echo -n $DRONE_DATABASE_DATASOURCE | kubeseal --raw --scope namespace-wide --namespace drone)
  yq -i '.spec.encryptedData.DRONE_DATABASE_DATASOURCE = strenv(SECRET_VALUE)' ./apps/public/drone/drone-secrets.yaml
}

update_harbor_secrets() {
  export SECRET_VALUE=$(echo -n $HARBOR_ADMIN_PASSWORD | kubeseal --raw --scope namespace-wide --namespace harbor)
  yq -i '.spec.encryptedData.adminPassword = strenv(SECRET_VALUE)' ./apps/homelab/harbor/harbor-secrets.yaml

  export SECRET_VALUE=$(echo -n $HARBOR_POSTGRES_PASSWORD | kubeseal --raw --scope namespace-wide --namespace harbor)
  yq -i '.spec.encryptedData.password = strenv(SECRET_VALUE)' ./apps/homelab/harbor/harbor-secrets.yaml
}

update_media_secrets() {
  export SECRET_VALUE=$(echo -n $OPENVPN_USER | kubeseal --raw --scope namespace-wide --namespace media)
  yq -i '.spec.encryptedData.OPENVPN_USER = strenv(SECRET_VALUE)' ./apps/media/gluetun-secrets.yaml

  export SECRET_VALUE=$(echo -n $OPENVPN_PASSWORD | kubeseal --raw --scope namespace-wide --namespace media)
  yq -i '.spec.encryptedData.OPENVPN_PASSWORD = strenv(SECRET_VALUE)' ./apps/media/gluetun-secrets.yaml

  kubectl create secret docker-registry regcred \
    --namespace=media \
    --docker-server=harbor.local.abbottland.io \
    --docker-username=$HARBOR_REG_USERNAME \
    --docker-password=$HARBOR_REG_PASSWORD \
    --docker-email=$HARBOR_REG_EMAIL \
    --output json --dry-run=client \
    | kubeseal \
      --scope namespace-wide \
      --namespace media \
      | yq --prettyPrint > ./apps/media/harbor-regcred.yaml

  export SECRET_VALUE=$(echo -n $QBITTORRENT_PASSWORD | kubeseal --raw --scope namespace-wide --namespace media)
  yq -i '.spec.encryptedData.QBITTORRENT_PASSWORD = strenv(SECRET_VALUE)' ./apps/media/qbittorrent-secrets.yaml
}

update_flux_system_secrets() {
  # This is needed for Flux to be able to pull images from Harbor for ImageUpdateAutomation
  kubectl create secret docker-registry regcred \
    --namespace=flux-system \
    --docker-server=harbor.local.abbottland.io \
    --docker-username=$HARBOR_REG_USERNAME \
    --docker-password=$HARBOR_REG_PASSWORD \
    --docker-email=$HARBOR_REG_EMAIL \
    --output json --dry-run=client \
    | kubeseal \
      --scope namespace-wide \
      --namespace flux-system \
      | yq --prettyPrint > ./clusters/homelab/harbor-regcred.yaml
}

echo "Starting to update secrets..."
update_cloudflare_secrets
# update_drone_secrets
# update_harbor_secrets
# update_media_secrets
# update_flux_system_secrets
echo "Done."