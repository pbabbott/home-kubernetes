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

