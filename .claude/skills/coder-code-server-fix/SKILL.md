# coder-code-server-fix

Use when code-server is unhealthy in a Coder workspace and needs to be fixed in the template, or when applying an emergency workaround to the running pod.

## Auth

```bash
TOKEN=$(grep CODER_TOKEN /home/firebolt/code/home-kubernetes/.env | cut -d= -f2)
BASE=https://coder.local.abbottland.io
ORG_ID=8aa3e329-80eb-4a8c-a674-2125c4788dc2
TEMPLATE_ID=06e4058e-58f5-4534-894a-9181c7b9d945  # kubernetes-ubuntu
```

## Emergency workaround (unblocks user immediately)

Run this in the pod to get code-server up without a restart:

```bash
POD=$(kubectl get pods -n coder-workspaces --context prod-gen2 -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash -c "
  if [ ! -f /tmp/code-server/bin/code-server ]; then
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
  fi
  (while true; do
    /tmp/code-server/bin/code-server --auth none --port 13337 --app-name code-server >> /tmp/code-server.log 2>&1
    sleep 3
  done) &
  sleep 2 && ps aux | grep code-server | grep -v grep
"
```

Note: this only survives until the next workspace restart. Fix the template to make it permanent.

## Correct template pattern for persistent code-server

Use `startup_script` in `coder_agent` with `#!/bin/bash --norc --noprofile`. The `--norc --noprofile` flags are **critical** — without them, bash sources `.bashrc`, which on this workspace does `exec zsh -l` and exits the script in ~50ms before any commands run.

Install from the PVC tarball cache (not via `curl | sh`) to avoid 4+ second network installs. Use `nohup setsid` so code-server survives the startup_script exiting, and wait for health before returning so the workspace only goes "ready" once code-server is listening.

### What does NOT work (and why)

| Approach | Why it fails |
|----------|-------------|
| `startup_script` without `--norc --noprofile` | `.bashrc` does `exec zsh -l`; zsh exits in ~50ms, nothing runs |
| `... &` backgrounded in startup_script | Works for setsid'd processes; bare `&` may not survive agent PGID cleanup |
| `coder_script` with `start_blocks_login = false` | Killed at the exact millisecond startup_script exits; both complete simultaneously |
| `timeout = 0` in coder_script | Invalid — provider requires >= 1; omit the field instead |
| `$$VAR` in Terraform heredoc | `$$` (no `{`) stays as `$$` in rendered output = shell PID, not variable |

### Correct `startup_script` pattern

```hcl
resource "coder_agent" "main" {
  # ...
  startup_script = <<-EOT
    #!/bin/bash --norc --noprofile
    # --norc --noprofile skips .bashrc, which on this workspace does `exec zsh -l`
    # and would silently exit the script in ~50ms before any commands run.
    mkdir -p ~/repos

    if [ ! -f /tmp/code-server/bin/code-server ]; then
      TARBALL=$(ls /home/coder/.cache/code-server/code-server-*-linux-amd64.tar.gz 2>/dev/null | head -1)
      if [ -n "$TARBALL" ]; then
        BASENAME=$(basename "$TARBALL" -linux-amd64.tar.gz)
        mkdir -p /tmp/code-server/lib /tmp/code-server/bin
        tar -xzf "$TARBALL" -C /tmp/code-server/lib
        mv -f "/tmp/code-server/lib/$BASENAME-linux-amd64" "/tmp/code-server/lib/$BASENAME"
        ln -sf "/tmp/code-server/lib/$BASENAME/bin/code-server" /tmp/code-server/bin/code-server
      else
        curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
      fi
    fi

    nohup setsid /tmp/code-server/bin/code-server --auth none --port 13337 --app-name code-server > /tmp/code-server.log 2>&1 &

    for i in $(seq 1 30); do
      curl -sf http://localhost:13337/healthz >/dev/null 2>&1 && break
      sleep 1
    done
  EOT
}
```

### Terraform heredoc variable escaping rules

In Terraform `<<-EOT` heredocs, only `${...}` and `%{...}` are template sequences:
- `$VAR` → passes through unchanged ✓
- `$(cmd)` → passes through unchanged ✓  
- `${VAR}` → **Terraform interpolation** → use `$${VAR}` to get bash `${VAR}`
- `$$VAR` → stays as `$$VAR` in output (= shell PID prefix) — **do NOT use**

Avoid `${VAR}` brace form entirely; use `$VAR` instead to sidestep escaping.

## Pushing a template fix

See the `coder-template-push` skill for the full upload/version/promote flow. Quick reference:

```bash
# 1. Download current template
FILE_ID=$(curl -s -H "Coder-Session-Token: $TOKEN" \
  "$BASE/api/v2/templateversions/$(curl -s -H "Coder-Session-Token: $TOKEN" "$BASE/api/v2/templates/$TEMPLATE_ID" | python3 -c "import sys,json; print(json.load(sys.stdin)['active_version_id'])")" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['job']['file_id'])")
curl -s -H "Coder-Session-Token: $TOKEN" "$BASE/api/v2/files/$FILE_ID" -o /tmp/template.tar
mkdir -p /tmp/coder-tpl && tar -xf /tmp/template.tar -C /tmp/coder-tpl

# 2. Edit /tmp/coder-tpl/main.tf

# 3. Repack
tar -cf /tmp/template-new.tar -C /tmp/coder-tpl main.tf

# 4. Upload, create version, wait, promote
NEW_FILE_ID=$(curl -s -X POST -H "Coder-Session-Token: $TOKEN" -H "Content-Type: application/x-tar" \
  --data-binary @/tmp/template-new.tar "$BASE/api/v2/files?content_type=application/x-tar" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['hash'])")

VERSION_ID=$(curl -s -X POST -H "Coder-Session-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"storage_method\":\"file\",\"file_id\":\"$NEW_FILE_ID\",\"provisioner\":\"terraform\",\"template_id\":\"$TEMPLATE_ID\",\"message\":\"your message\"}" \
  "$BASE/api/v2/organizations/$ORG_ID/templateversions" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

until curl -s -H "Coder-Session-Token: $TOKEN" "$BASE/api/v2/templateversions/$VERSION_ID" | \
  python3 -c "import sys,json; s=json.load(sys.stdin)['job']['status']; print(s); exit(0 if s in ('succeeded','failed') else 1)"; do sleep 3; done

# Promote — NOTE: PATCH /templates/:id with active_version_id does NOT work
curl -s -X PATCH -H "Coder-Session-Token: $TOKEN" -H "Content-Type: application/json" \
  -d "{\"id\": \"$VERSION_ID\"}" "$BASE/api/v2/templates/$TEMPLATE_ID/versions" | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('message','?'))"
```

## Diagnosing why code-server isn't running

```bash
POD=$(kubectl get pods -n coder-workspaces --context prod-gen2 -o jsonpath='{.items[0].metadata.name}')

# What script actually ran?
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash -c "
  grep -A 25 'running agent script' /tmp/coder-agent.log | head -30
"

# Did it complete fast (< 200ms)? Install was skipped or failed silently.
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash -c "
  grep 'script completed' /tmp/coder-agent.log
"

# Is the binary there?
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash -c "
  ls -la /tmp/code-server/bin/ 2>/dev/null || echo 'NOT INSTALLED'
"

# Is code-server running?
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash -c "
  ps aux | grep code-server | grep -v grep
  cat /tmp/code-server.log 2>/dev/null | tail -10
"
```
