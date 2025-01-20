
# Secrets - Cloudflare API Token

The purpose of this document is to explain how the cloudflare api token is setup and how it can be rotated.

## Overview

The cloudflare API token exists in two different namespaces: 

- `external-dns` - This allows CNAME records to be managed for my publicly facing URLs
- `cert-manager` - This allows LetsEncrypt to verify DNS ownership via TXT records for both internal/external URLs

In the `external-dns` namespace, the secret is used in the `HelmRelease` and the `secretName` needs to be `cloudflare-api-token-secret` and the key within the secret needs to be: `cloudflare_api_token` as per the `external-dns` helm chart docs. 

The secret also needs to exist in the `cert-manager` namespace.  The secret name should be `cloudflare-api-token-secret` and the key within the secret needs to be: `cloudflare_api_token` a

- The `ClusterIssuer` needs a reference to the secret in `cert-manager`
- The `cloudflare-ddns` service in `cert-manager` also needs this secret to exist.

## Update Procedure

Updating this secret is easy, as the secret just needs to be updated in the `1Password` UI, and then it propagate to all the various services.

- Step 1 - Login to cloudflare.com
- Step 2 - Go to API Tokens: https://dash.cloudflare.com/profile/api-tokens
- Step 3 - Create a new token
- Step 4 - Use template for edit zone DNS
- Step 5 - Fill out the form
  - Zone DNS Edit
  - I chose abbottland.io
  - No client filtering
  - TTL is 1 year

