# Non-Prod Gen2 Cluster Rebuild — op-connect Re-seal

After rebuilding the non-prod gen2 cluster, `op-credentials` SealedSecret cannot
decrypt because the Sealed Secrets controller generates a new key pair on first boot.
The old ciphertext is cluster-specific and not portable.

## Status

- [x] Longhorn CRDs added to `crds-ks` (fixes RecurringJob dry-run deadlock)
- [ ] Re-seal `op-credentials` with new cluster key
- [ ] Verify `infra-ks` goes green
- [ ] Verify `apps-ks` unblocks

## Steps

### 1. Get credentials from 1Password

- Item: `Kubernetes Non-Prod Gen2 Credentials File` (Homelab vault)
- Save to repo root as `1password-credentials-nonprod.json` (already in `.gitignore`)

### 2. Set token in .env

```sh
OP_CONNECT_TOKEN_NONPROD=<token from 1Password>
```

Token is stored in 1Password alongside the credentials file.

### 3. Re-seal (kubectl context must be nonprod-gen2)

```sh
kubectx nonprod-gen2

OP_CONNECT_CREDENTIALS_FILE=./1password-credentials-nonprod.json \
OP_CONNECT_SEALED_SECRET_OUTPUT=./infra/non-prod-gen2/onepassword/op-credentials.yaml \
./scripts/op-connect-secret.sh
```

### 4. Commit and push

```sh
git add infra/non-prod-gen2/onepassword/op-credentials.yaml
git commit -m "fix(op-connect): re-seal credentials for nonprod-gen2 after cluster rebuild"
git push
```

### 5. Verify cascade

```sh
flux get kustomization -A
flux get helmrelease op-connect -n flux-system
```

Once `op-connect` is `True`, `cert-manager` and `external-dns-pihole` HelmReleases
(which `dependsOn: op-connect`) will unblock, then `infra-ks` → `apps-ks` should go green.

### 6. Cleanup

Delete credential file from repo root after script completes:
```sh
rm 1password-credentials-nonprod.json
```
