# Archived clusters

The code for the first two cluster generations was removed from this repo on 2026-11 (gen3 /
`prod-gen3` is the only live cluster). It is preserved at git tags; the pages here describe what
each cluster ran so you can answer "how did I used to do that?" without checking out old code.

| Cluster | Overview | Tag | Status |
| --- | --- | --- | --- |
| Gen 1 `homelab` | [gen1-homelab.md](./gen1-homelab.md) | `archive-gen1-homelab` | dead (replaced by gen2 in 2026-03) |
| Gen 2 `prod-gen2` | [gen2-prod.md](./gen2-prod.md) | `archive-gen2-prod` | retired 2026-11-09 (replaced by gen3) |
| Gen 2 `non-prod-gen2` | [gen2-nonprod.md](./gen2-nonprod.md) | `archive-gen2-nonprod` | powered off (host out of resources), never migrated |

All three tags point at the same commit, **`c32de0ea63f537c4fcaa0be758e28f31e2924691`**
(2026-11-08, "gen3: stage proxmox, asustor, haproxy, plex"). It is the last commit on `main` where gen1,
prod-gen2 and non-prod-gen2 were all complete: the first gen2 apps were pruned in the next commit
(`4acaa51`, the proxmox flip), so a later commit shows an increasingly empty `applications/prod-gen2`.

## How to look at it

```sh
git fetch --tags
git ls-tree -r archive-gen2-prod --name-only -- applications/prod-gen2   # list files
git show archive-gen2-prod:applications/prod-gen2/kustomization.yaml    # read one file
git checkout archive-gen2-prod -- applications/prod-gen2/blog            # restore a dir into the worktree
```

On GitHub: https://github.com/pbabbott/home-kubernetes/tree/archive-gen2-prod

Directories at the tag:

| Cluster | Paths |
| --- | --- |
| Gen 1 | `apps/`, `infrastructure/`, `clusters/homelab/` |
| Gen 2 prod | `clusters/prod-gen2/`, `crds/prod-gen2/`, `infra/prod-gen2/`, `applications/prod-gen2/` |
| Gen 2 non-prod | `clusters/non-prod-gen2/`, `crds/non-prod-gen2/`, `infra/non-prod-gen2/`, `applications/non-prod-gen2/` |

`apps/base/` (`applications/base/` at the tag), `infra/base/` and `crds/base/` were shared with gen3 and still exist on `main`; at the tag
they are in their gen2-era state.

> Note for Claude: when asked how gen1 or gen2 did something, read these pages first, then inspect the tag with
> the commands above. Do not expect these directories on `main`, and do not restore them without being asked.

Related history that stays on `main`: `docs/plans/2026-11-08-gen2-to-gen3-migration.md` (the migration, with
per-app learnings), `docs/plans/2026-05-21-prod-gen2-cluster-rebuild.md`, `docs/incidents/`, `docs/claude-sessions/`.
Host and VM details: `home-playbooks/docs/HOSTS.md` and `home-playbooks/docs/ARCHIVE.md`.
