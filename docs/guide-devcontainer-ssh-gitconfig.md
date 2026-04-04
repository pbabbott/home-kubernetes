# Dev Containers over SSH: `.gitconfig` / authority resolution fix

This document describes a **repeatable workaround** for Cursor/VS Code when using **Dev Containers on a Remote-SSH host** (or similar nested-remote setups). Use it as instructions for a human or an AI agent applying the same fix in **other repositories**.

## Symptoms

- After disconnecting and reconnecting (or on a fresh rebuild), Dev Containers fails with:
  - `Failed to read .gitconfig: TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string. Received undefined`
  - `Error resolving dev container authority The "path" argument must be of type string. Received undefined`
- Log may also show: `Shutdown action is supported only for local exec servers or wsl`

## Cause (short)

The Dev Containers extension tries to **read and copy** a host `~/.gitconfig` into the container. In chained **Local → SSH → Container** scenarios, the path it builds can be **`undefined`**, which triggers the Node error above. This is **not** fixed by rebuilding the image and is **not** explained by full disk on the VM (`no space left on device` would look different).

## What actually fixes it

Do **both** of the following so the extension skips the broken copy step **and** Git identity still works inside the container:

1. **Disable automatic gitconfig copy** (`dev.containers.copyGitConfig: false`) where the resolver will see it early enough.
2. **Bind-mount** the SSH user’s `~/.gitconfig` into the dev container user’s home (read-only), similar to `~/.ssh`.

Setting the flag **only** in `devcontainer.json` may be **too late**; the workspace settings file is still required in practice.

## Why the same failure can look “random” (including after a fresh rebuild)

A **rebuild only recreates the container image/instance**. The bug is in **Cursor/VS Code + Dev Containers + Remote-SSH** layering (paths and URIs that are not always defined on every code path). That layer does not become deterministic just because Docker started cleanly.

You may see this pattern in logs:

1. **Devcontainer CLI / configuration**: `outcome: success`, `containerId` set, mounts applied (including `~/.gitconfig`), `Finished Read Dev Container Configuration: success`.
2. **Next line**: `Installing remote server in container...`
3. **Then**: `Error resolving dev container authority The "path" argument must be of type string. Received undefined`

If **`Failed to read .gitconfig` is absent**, the gitconfig workaround **did run**; the crash is then coming from a **different** `fs`/`path` call during **server install / authority resolution** (still `undefined` where a string path is required). Older runs might show **both** messages depending on order and caching.

So **inconsistency is expected**: several steps can throw the same Node error; timing, which settings were loaded first (local vs remote workspace), and extension version can change **which** line fails first or whether you get past gitconfig.

**Mitigations when the container is already up but the window fails:**

- **Local** Cursor **User** settings: set `dev.containers.copyGitConfig` to `false` (the resolver partly runs on the machine where the UI is, before everything on the SSH host is wired).
- Use **Dev Containers: Attach to Running Container…** and pick the `vsc-…` container (workaround when auto-connect stalls).
- **Developer: Reload Window** and retry once (clears a bad resolver pass without rebuilding).
- Keep **Dev Containers**, **Remote - SSH**, and **Cursor** updated; chained-remote bugs are patched over time.

---

## AI agent checklist

When asked to apply this fix to a repo that uses Dev Containers:

1. Open `.devcontainer/devcontainer.json` (or the project’s devcontainer config path).
2. Ensure **`customizations.vscode.settings`** includes `"dev.containers.copyGitConfig": false` (merge with existing `vscode` keys; do not remove unrelated extensions or settings).
3. Ensure **`mounts`** includes a **readonly** bind mount from the **SSH host** user’s gitconfig to the **container dev user**’s `~/.gitconfig`:
   - `type=bind,source=/home/${localEnv:USER}/.gitconfig,target=/home/<remoteUser>/.gitconfig,readonly`
   - Replace `<remoteUser>` with the dev container’s non-root user (often `vscode`; match `remoteUser` / `containerUser` in the same file).
4. Open or create **`.vscode/settings.json`** at the repo root and set `"dev.containers.copyGitConfig": false` (preserve existing keys).
5. If the user still hits **`Error resolving dev container authority`** even when logs show **successful** devcontainer configuration and **no** `Failed to read .gitconfig`: explain that a **second** undefined-path bug may fire during **installing the remote server**; repo-level fixes cannot patch that—direct them to **local User** `dev.containers.copyGitConfig`, **Attach to Running Container**, reload window, and extension/app updates (see section above).
6. If the user still hits the error early (gitconfig line present): tell them to set `dev.containers.copyGitConfig` in **Cursor/VS Code User settings** on the **local** machine (and optionally **Remote [SSH]** scope), because part of the resolver runs locally before remote workspace settings apply.
7. Do **not** duplicate or remove unrelated devcontainer options (`features`, `postStartCommand`, secrets, etc.).

---

## Reference snippets

### `.vscode/settings.json` (merge into existing object)

```json
"dev.containers.copyGitConfig": false
```

### `devcontainer.json` fragments

**`mounts`** — add the gitconfig line alongside existing mounts (e.g. `.ssh`):

```json
"mounts": [
  "type=bind,source=/home/${localEnv:USER}/.ssh,target=/home/vscode/.ssh,readonly",
  "type=bind,source=/home/${localEnv:USER}/.gitconfig,target=/home/vscode/.gitconfig,readonly"
]
```

**`customizations.vscode.settings`**:

```json
"customizations": {
  "vscode": {
    "settings": {
      "dev.containers.copyGitConfig": false
    }
  }
}
```

Adjust `/home/vscode/` if your dev container user is not `vscode`.

---

## Optional verification on the SSH host

- `~/.gitconfig` should exist and not be an empty file (empty `~/.gitconfig` is a known edge case upstream).
- Disk space: lack of space is **not** the typical signature of this bug; this failure is an **undefined path** in the extension, not `ENOSPC`.

---

## Security note

Dev Containers / `docker inspect` logs can include **environment variables** (tokens). Redact logs before sharing; rotate any secrets that appeared in a log file.
