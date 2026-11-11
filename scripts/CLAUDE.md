# scripts/

Helpers for working on the cluster. Run from the repo root (`./scripts/x.sh`). They talk to the live `prod-gen3`
cluster through `kubectl` (context `prod-gen3`), so be on the right context first; the devcontainer provides `kubectl`,
`kubeseal`, `op`, `jq` and `yq`. Enable the manifest check once per clone with `pre-commit install`.

## Manifest

Every file in this dir has exactly one row here (enforced by `check-manifest.sh`, a pre-commit hook).

| Script | Use | What it does |
|---|---|---|
| `op-connect-secret.sh` | run | Re-seals the 1Password Connect credentials (`op-credentials` SealedSecret incl. token) for the cluster `kubeseal` points at. Reads `./1password-credentials*.json` (gitignored, from the Homelab vault) and tokens from `.env` (`OP_CONNECT_TOKEN_PROD` when the file name contains `prod`). Writes `infra/prod-gen3/secrets/onepassword/op-credentials.yaml` (override with `OP_CONNECT_SEALED_SECRET_OUTPUT`). Procedure: `docs/ai-reference/secrets.md`. |
| `get-grafana-api-key.sh` | run | Prints a Grafana service-account token (`automation` SA) via port-forward to the in-cluster Grafana. Creates a new token on every run. Env: `KUBE_CONTEXT`, `GRAFANA_SA_NAME`. |
| `dev-grafana-dashboards.py` | run | Watches `infra/base/observability/kube-prometheus-stack/dashboards/` and hot-pushes changed dashboard JSON to Grafana (`-dev` UID copies; `--prod` pushes the real UIDs). Gets its token from `get-grafana-api-key.sh`. |
| `longhorn-restore.sh` | run | Restores a Longhorn backup into a PVC with the exact name/namespace/size an app expects. Dry-run by default; `--apply` to create, `--cleanup` to undo. Built for the gen2 to gen3 data move (`docs/ai-reference/gen3-data-move.md`); gen2 is gone but its backups remain on the NAS until issue #40, so re-evaluate then. |
| `check-manifest.sh` | pre-commit | Fails if a file here has no row in this table, or a row names a missing file. |

## Common workflows

- **Re-seal 1Password Connect credentials** (cluster rebuild): follow `docs/ai-reference/secrets.md`, which ends in `scripts/op-connect-secret.sh`; delete the credentials file and `./temp` afterwards.
- **Grafana token** (for the grafana MCP in `.mcp.json`): `export GRAFANA_TOKEN_PROD=$(./scripts/get-grafana-api-key.sh)`.
- **Iterate on a dashboard:** `./scripts/dev-grafana-dashboards.py`, edit the JSON (it must carry the `gitops-managed` tag), check the `-dev` copy in Grafana; `--prod` only when intentionally overwriting the real one.
- **Restore a Longhorn backup:** run `./scripts/longhorn-restore.sh ...` as a dry-run first, then add `--apply`.

## Keeping this current

When you add, rename, change the purpose of, or remove a script, in the same commit update: the manifest table above,
the Scripts section in `../CLAUDE.md` and `../README.md` if a workflow changed, and any doc that names the script.
Prefer one script per job; don't leave back-compat wrappers (delete and fix the docs instead; git history keeps them).
