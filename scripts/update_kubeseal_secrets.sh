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


echo "Starting to update secrets..."
# update_drone_secrets
echo "Done."