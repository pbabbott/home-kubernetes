#!/usr/bin/env bash
# SCP kubeconfigs from each controller, prefix cluster/user/context names with yq so
# names never collide, then kubectl config view --flatten into ~/.kube/config.
#
# We transform YAML with yq (not kubectl -o json | jq): kubectl's JSON output
# redacts cert material to "DATA+OMITTED", which breaks TLS for kubectl get pods, etc.
#
# CONTROLLERS labels: clusters/users are always "<label>-<original>".
# Context names: if that kubeconfig has one context, the name is exactly the label (kubectx:
# prod-gen2, nonprod-gen2). If it has several, each becomes "<label>-<original>" so nothing collides.
#
# Optional: KUBE_CONTEXT_AFTER_MERGE=…  KUBE_NS_AFTER_MERGE=…

set -euo pipefail

USER="${KUBE_SSH_USER:-firebolt}"
TMP_FILES=()

CONTROLLERS=(
  # "192.168.4.193:prod-gen1"
  "192.168.6.24:prod-gen2"
  "192.168.6.31:nonprod-gen2"
)

die() { echo "error: $*" >&2; exit 1; }

cleanup() {
  local f
  for f in "${TMP_FILES[@]}"; do
    [[ -n "$f" ]] || continue
    rm -f -- "$f"
  done
}

require_cmds() {
  command -v yq >/dev/null 2>&1 || die "yq is required (mikefarah/yq v4)"
}

# Prefix YAML from the node so merged kubeconfigs never share cluster/user/context names.
# Certificate blobs are untouched.
prefix_kubeconfig_yaml() {
  local raw=$1 prefix=$2 out=$3
  local n

  n="$(yq e '.contexts | length' "$raw")"
  [[ "$n" =~ ^[0-9]+$ ]] || die "could not read context count from $raw"
  ((n > 0)) || die "no contexts in $raw"

  export MYPREFIX="$prefix"
  yq e '
    .clusters |= map(.name = strenv(MYPREFIX) + "-" + .name) |
    .users |= map(.name = strenv(MYPREFIX) + "-" + .name) |
    .contexts |= map(
        .context |= (
          .cluster = strenv(MYPREFIX) + "-" + .cluster |
          .user = strenv(MYPREFIX) + "-" + .user
        ) |
        .name = strenv(MYPREFIX)
      ) |
    .current-context = strenv(MYPREFIX)
  ' "$raw" >"$out"
  
}

main() {
  require_cmds
  trap cleanup EXIT

  mkdir -p "${HOME}/.kube"
  local dest="${HOME}/.kube/config"
  [[ -f "$dest" ]] && cp -a "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)"

  local -a merged=()
  local entry host name raw out

  for entry in "${CONTROLLERS[@]}"; do
    host="${entry%%:*}"
    name="${entry##*:}"
    raw="$(mktemp)"
    out="$(mktemp)"
    TMP_FILES+=("$out")

    echo "fetching ${USER}@${host} -> context ${name}"
    scp "${USER}@${host}:~/.kube/config" "$raw"
    prefix_kubeconfig_yaml "$raw" "$name" "$out"
    rm -f -- "$raw"
    merged+=("$out")
  done

  local new_cfg="${HOME}/.kube/config.new.$$"
  export KUBECONFIG
  KUBECONFIG=$(IFS=:; echo "${merged[*]}")
  kubectl config view --flatten >"$new_cfg"
  unset KUBECONFIG

  mv "$new_cfg" "$dest"
  echo "wrote ${dest} (contexts: $(kubectl config get-contexts -o name | paste -sd, -))"

  if [[ -n "${KUBE_CONTEXT_AFTER_MERGE:-}" ]]; then
    kubectl config use-context "$KUBE_CONTEXT_AFTER_MERGE"
  fi
  if [[ -n "${KUBE_NS_AFTER_MERGE:-}" ]]; then
    kubens "$KUBE_NS_AFTER_MERGE"
  fi
}

main "$@"
