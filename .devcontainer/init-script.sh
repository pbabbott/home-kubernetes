#!/usr/bin/env bash
# Manual / legacy: runs full setup. Dev container uses init-postcreate.sh + init-poststart.sh.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/init-postcreate.sh"
"$DIR/init-poststart.sh"
