# code-server Startup Debugging Log

Workspace: `home-dev` (template: `kubernetes-ubuntu`, Coder v2.34.2)
Pod namespace: `coder-workspaces`, cluster: `prod-gen2`

## Environment facts

- PVC at `/home/coder` (Longhorn, persists across restarts)
- `/tmp` is ephemeral — lost on every pod restart
- code-server tarball cached at `/home/coder/.cache/code-server/code-server-4.123.0-linux-amd64.tar.gz`
- `tar -xzf` of the 155 MB tarball takes ~4 seconds
- zsh installed at `/home/coder/.zsh-bin/bin/zsh`
- **`/home/coder/.bashrc` unconditionally does `exec zsh -l` if zsh exists** (no interactive guard)

## Root cause (confirmed)

The Coder agent runs the startup_script in a bash session that sources `.bashrc`. The `.bashrc` does `exec "$HOME/.zsh-bin/bin/zsh" -l`, which replaces bash with zsh. Zsh exits immediately (no TTY, no script), returning exit code 0 in ~50–80ms. The agent considers the script done. **Nothing in the startup_script ever executes.**

Symptom: `execution_time=53–96ms`, `exit_code=0`, startup log empty, binary not installed.

## Template API gotchas

- Template tar upload uses plain tar (not gzip): `tar -cf` / `Content-Type: application/x-tar`
- Template download is also plain tar: `tar -xf` (not `-xzf`)
- Promote endpoint: `PATCH /api/v2/templates/:id/versions` with body `{"id": "$VERSION_ID"}` — NOT `PATCH /api/v2/templates/:id` with `active_version_id` (that silently does nothing)
- Auth header: `Coder-Session-Token: $TOKEN`

## Things tried (in order)

### 1. `startup_script` with `&` backgrounding
```bash
/tmp/code-server/bin/code-server ... > /tmp/code-server.log 2>&1 &
```
**Result:** Failed. Even if the install had run, backgrounded children are killed when the startup_script exits (agent manages the process group).

### 2. `coder_script` resource with `start_blocks_login = false`
```hcl
resource "coder_script" "code_server" {
  start_blocks_login = false
  script = "while true; do code-server; sleep 3; done"
}
```
**Result:** Failed. The `coder_script` process is killed at the exact millisecond the startup_script exits (both complete simultaneously). Even with `start_blocks_login = false`, the agent cancels non-blocking scripts when blocking scripts complete. Confirmed: `execution_time=96ms` for startup, `execution_time=102ms` for coder_script — 6ms apart.

### 3. `setsid` in startup_script
```bash
setsid /tmp/code-server/bin/code-server ... &
```
**Result:** Not properly tested from within the agent. Works fine from `kubectl exec` (confirmed running after 3s). From agent context, the install never ran (see root cause below), so this was never actually exercised.

### 4. `nohup setsid` + health-wait loop
```bash
nohup setsid /tmp/code-server/bin/code-server ... &
for i in $(seq 1 30); do curl -sf .../healthz && break; sleep 1; done
```
**Result:** Never executed — startup_script was silently replaced by zsh (see root cause). Terraform variable escaping was also broken (`$$TARBALL` → PID, not variable).

### 5. Terraform heredoc variable escaping bug
Used `$$TARBALL`, `$$BASENAME`, `$$(ls ...)`, `$$(seq ...)` thinking Terraform required `$$` to escape `$`.

**Actual Terraform escaping rules:**
- `${FOO}` → Terraform interprets as interpolation → ERROR
- `$${FOO}` → renders as `${FOO}` in the script (bash brace expansion)
- `$FOO` → passes through unchanged (safe, no escaping needed)
- `$(cmd)` → passes through unchanged (safe, no escaping needed)
- `$$` NOT followed by `{` → stays as `$$` in rendered output → bash PID!

**Result:** `TARBALL` was set to the shell's PID string, not the tarball path. Install silently did nothing.

### 6. `exec > /tmp/startup-debug.log 2>&1` for debugging
Added as the first line of startup_script to redirect output.

**Result:** File was never created. Because the `.bashrc` zsh exec happens before any script line runs, the redirect never executed. This actually helped diagnose the root cause.

## Fix (CONFIRMED WORKING)

Use `#!/bin/bash --norc --noprofile` shebang to prevent bash from sourcing `.bashrc`:

```bash
#!/bin/bash --norc --noprofile
# --norc --noprofile skips .bashrc and .bash_profile,
# preventing the `exec zsh -l` in .bashrc from hijacking the script.
```

Also use absolute path for tarball glob to avoid tilde-expansion ambiguity:
```bash
TARBALL=$(ls /home/coder/.cache/code-server/code-server-*-linux-amd64.tar.gz 2>/dev/null | head -1)
```

**Confirmed result:** `execution_time=4.791668s`, `exit_code=0`, code-server healthy at i=2.
Template version `062f65c2` is the clean production version (no debug logging).

## Emergency workaround (unblocks immediately without restart)

```bash
POD=$(kubectl get pods -n coder-workspaces --context prod-gen2 -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash --norc --noprofile -c "
  TARBALL=\$(ls /home/coder/.cache/code-server/code-server-*-linux-amd64.tar.gz 2>/dev/null | head -1)
  if [ -n \"\$TARBALL\" ]; then
    BASENAME=\$(basename \"\$TARBALL\" -linux-amd64.tar.gz)
    mkdir -p /tmp/code-server/lib /tmp/code-server/bin
    tar -xzf \"\$TARBALL\" -C /tmp/code-server/lib
    mv -f /tmp/code-server/lib/\${BASENAME}-linux-amd64 /tmp/code-server/lib/\${BASENAME}
    ln -sf /tmp/code-server/lib/\${BASENAME}/bin/code-server /tmp/code-server/bin/code-server
  fi
  nohup setsid /tmp/code-server/bin/code-server --auth none --port 13337 --app-name code-server > /tmp/code-server.log 2>&1 &
  sleep 3 && ps aux | grep code-server | grep -v grep
"
```

Note: survives only until next pod restart. Fix the template for permanent solution.

## Diagnostic commands

```bash
POD=$(kubectl get pods -n coder-workspaces --context prod-gen2 -o jsonpath='{.items[0].metadata.name}')

# Check if script ran at all and how long it took
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash --norc -c \
  "grep 'script completed\|execution_time' /tmp/coder-agent.log"

# See what script the agent actually received and ran
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash --norc -c \
  "grep -A 30 'running agent script' /tmp/coder-agent.log | head -35"

# Check PVC debug log (if using the debug template version)
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash --norc -c \
  "cat /home/coder/startup-debug.log"

# Check code-server process and port
kubectl exec -n coder-workspaces $POD --context prod-gen2 -- bash --norc -c \
  "ps aux | grep code-server | grep -v grep; ss -tlnp | grep 13337"
```
