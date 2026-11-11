# Secrets in home-kubernetes (gen3)

Two layers. **Sealed Secrets exists only to bootstrap 1Password.** Everything else is 1Password.

```
git ──► SealedSecret `op-credentials` ──(sealed-secrets controller, kube-system)──► Secret op-connect/op-credentials
                                                                                        │
                                                1Password Connect + operator (ns op-connect) ◄┘
                                                        │
        1Password vault "Homelab" ──► OnePasswordItem (any ns) ──► Secret (same ns, same name)
```

## Layer 1 – Sealed Secrets (bootstrap only)
- Controller: HelmRelease `sealed-secrets` (`infra/base/secrets/sealed-secrets`), deployed in `kube-system` as `sealed-secrets-controller`. Gen3 has its **own key**; ciphertext is not portable between clusters.
- The only SealedSecret on gen3: `infra/prod-gen3/secrets/onepassword/op-credentials.yaml` (scope `namespace-wide`, namespace `op-connect`, keys `1password-credentials.json` + `token`).
- **Key backup:** 1Password Secure Note `sealed-secrets-key-prod-gen3` in vault Homelab (full Secret YAML, label `sealedsecrets.bitnami.com/sealed-secrets-key`).
- **Rebuild / DR (not yet rehearsed):** before Flux installs the controller, apply that Secret into `kube-system`, then start the controller; existing SealedSecrets decrypt unchanged, no re-seal. Without the key, re-seal `op-credentials` (below).
- Only add a new SealedSecret when 1Password can't do it (e.g. `regcred` needs a dockerconfigjson transform, see `docs/secrets-regcred.md`). Procedure: `docs/dev-guide-sealed-secrets-create-manifest.md`.

## Layer 2 – 1Password Connect + operator (everything else)
- HelmRelease `op-connect` (`infra/base/secrets/onepassword`, gen3 overlay `infra/prod-gen3/secrets/onepassword`): Connect API (`svc/onepassword-connect:8080`) and the operator, namespace `op-connect`. `dependsOn` sealed-secrets. No HTTPRoute on gen3 until istio (Phase 4).
- To give an app a secret (default, "option A"):
  1. Create/edit the item in the **Homelab** vault (UI). Field labels become Secret keys; the item title must equal the `itemPath` exactly.
  2. Add a `OnePasswordItem` next to the app (`<name>-<kind>.yaml`, e.g. `infra/base/networking/cert-manager/cloudflare-api-token-onepassword.yaml`):
     ```yaml
     apiVersion: onepassword.com/v1
     kind: OnePasswordItem
     metadata:
       name: my-secret            # becomes the Secret name
       namespace: my-ns
       annotations:
         operator.1password.io/auto-restart: "true"   # optional: restart consumers on change
     spec:
       itemPath: "vaults/Homelab/items/<exact item title>"
     ```
  3. Anything consuming it from a HelmRelease/Kustomization should `dependsOn` `op-connect`.
- Debugging: `docs/ai-reference-onepassword-operator.md` (status, force reconcile, key-name mismatch). Browsing the vault via the API: `docs/ai-reference-op-connect-api-access.md`.
- Per-secret notes live in `docs/secrets-*.md`.

## Current gen3 state / caveats
- Gen3's `op-credentials` was **copied from gen2's live secret** and re-sealed for gen3's key, so gen3 uses the same Connect credentials/token as gen2 (each cluster runs its own Connect pod). **When decommissioning gen2, do not revoke that Connect server/token in 1Password**; gen3 depends on it. If a separate gen3 identity is wanted later, create a new Secrets Automation workflow and re-seal.
- Re-seal / rotate `op-credentials` on gen3 (context `prod-gen3`, controller must be running):
  1. Download `1password-credentials.json` from the Homelab vault Document **"Kubernetes Production Credentials File"** (created when gen2 was set up; this is the Connect server both gen2 and gen3 use, despite the "Prod Gen2" names in older docs) and save it as `./1password-credentials-prod.json`. The matching token goes in `.env` as `OP_CONNECT_TOKEN_PROD`.
  2. Run `OP_CONNECT_CREDENTIALS_FILE=./1password-credentials-prod.json OP_CONNECT_SEALED_SECRET_OUTPUT=./infra/prod-gen3/secrets/onepassword/op-credentials.yaml scripts/op-connect-secret.sh`, commit, merge.
  3. Delete the credentials file and `./temp` afterwards; never print values.
  (On 2026-11-08 neither file was on disk, so the secret was instead piped from gen2's live Secret into `kubeseal --context prod-gen3 --scope namespace-wide --namespace op-connect`.)
- **Claude/dev-shell access:** `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` are set and **read-only**. `op item get <title> --vault Homelab --format json` works; `op item list/create`, `op whoami`, and REST creates (403) do not. Writing to 1Password needs the UI or a real `op signin`.
- Never commit plaintext Secrets or credential files (`1password-credentials*.json`, `.env`, `temp/` are gitignored).

## Older docs
`reference-secret-management-strategy.md` (why two layers) and `reference-1password-integration-overview.md` (original setup) are gen2-era; use this doc for gen3.
