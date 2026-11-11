#!/usr/bin/env bash
# Pre-commit check: every file in scripts/ (except CLAUDE.md) must have a row in scripts/CLAUDE.md's manifest,
# and every manifest row must name an existing file.
set -euo pipefail
cd "$(dirname "$0")"
on_disk=$(ls -1 | grep -v '^CLAUDE.md$' | sort)
in_doc=$(grep -oE '^\| `[^`]+`' CLAUDE.md | sed -E 's/^\| `([^`]+)`/\1/' | sort)
missing_doc=$(comm -23 <(echo "$on_disk") <(echo "$in_doc"))
missing_file=$(comm -13 <(echo "$on_disk") <(echo "$in_doc"))
rc=0
[ -z "$missing_doc" ] || { echo "scripts/CLAUDE.md has no row for: $missing_doc" >&2; rc=1; }
[ -z "$missing_file" ] || { echo "scripts/CLAUDE.md lists missing files: $missing_file" >&2; rc=1; }
exit $rc
