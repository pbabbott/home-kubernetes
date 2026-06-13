---
name: coder-workspace-debug
description: Debug a failing Coder workspace build — check HelmRelease, pod state, and build logs via API
---

User provides a workspace name or says a workspace is failing. Follow these steps.

## Auth

Token in `.env` as `CODER_TOKEN`. Base URL: `https://coder.local.abbottland.io`.

```bash
TOKEN=$(grep CODER_TOKEN /workspaces/home-kubernetes/.env | cut -d= -f2)
BASE=https://coder.local.abbottland.io
```

## Step 1: Check Coder HelmRelease

```bash
kubectl get helmrelease coder -n flux-system --context prod-gen2 -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

If `RetriesExceeded`: Flux gave up. Run:
```bash
flux reconcile helmrelease coder -n flux-system --reset --context prod-gen2 &
```

## Step 2: Check workspace + build status

```bash
curl -s -H "Coder-Session-Token: $TOKEN" "$BASE/api/v2/workspaces?q=<name>" | \
  python3 -c "
import sys,json
v=json.load(sys.stdin)['workspaces'][0]
b=v['latest_build']
print('Workspace:', v['id'])
print('Build:', b['id'], '| Status:', b['status'])
print('Error:', b['job'].get('error','none'))
"
```

## Step 3: Get build logs

```bash
BUILD_ID=<from step 2>
curl -s -H "Coder-Session-Token: $TOKEN" "$BASE/api/v2/workspacebuilds/$BUILD_ID/logs" | \
  python3 -c "import sys,json; [print(l['output']) for l in json.load(sys.stdin) if l.get('output','').strip()]" | \
  grep -E "Error|error|forbidden|failed|Fallback" | grep -v "deprecated"
```

## Step 4: Check pod logs

```bash
kubectl get pods -n coder-workspaces --context prod-gen2
kubectl logs -n coder-workspaces <pod> --context prod-gen2 2>&1 | head -60
```

Also check `coder` namespace for the server pod:
```bash
kubectl get pods -n coder --context prod-gen2
kubectl logs -n coder <coder-pod> --context prod-gen2 2>&1 | tail -30
```

## Common failures and fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `cannot create resource in namespace "default"` | Template `namespace` var = `"default"` | Create new template version with `user_variable_values: [{name: namespace, value: coder-workspaces}]` — see `coder-template-push` skill |
| `database "coderdb" does not exist` | DB not created on NAS postgres | `CREATE DATABASE coderdb;` on NAS |
| `exec: "git": executable file not found` | envbuilder got `owner/repo` not full URL | Pass `https://github.com/owner/repo` — or fix template `repo_url` local |
| `Falling back to the default image` | devcontainer.json not found or build failed | Check `/workspaces/<repo>/.devcontainer/` exists in pod |
| `RetriesExceeded` | Helm install timed out (pod never Ready) | `flux reconcile helmrelease coder -n flux-system --reset --context prod-gen2` |
| `CrashLoopBackOff` | Coder server crashing | Check coder pod logs for DB connection errors |

## Template variable override pattern

When a build uses wrong stored variable values (e.g. `namespace=default`), the fix is NOT to patch — create a new version:

```bash
# Upload tar, then:
curl -s -X POST -H "Coder-Session-Token: $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "storage_method": "file",
    "file_id": "<file_hash>",
    "provisioner": "terraform",
    "template_id": "<template_id>",
    "user_variable_values": [
      {"name": "namespace", "value": "coder-workspaces"},
      {"name": "use_kubeconfig", "value": "false"}
    ]
  }' "$BASE/api/v2/organizations/<org_id>/templateversions"
```

Terraform state from a prior build persists across rebuilds — if namespace was wrong in state, delete workspace entirely and recreate.
