#!/usr/bin/env bash
# Runs once when the dev container is created (not on every open).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Fetching oh-my-zsh plugins"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
export GIT_TERMINAL_PROMPT=0
_plugins=(
  "https://github.com/zsh-users/zsh-autosuggestions|${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  "https://github.com/MichaelAquilina/zsh-you-should-use.git|${ZSH_CUSTOM}/plugins/you-should-use"
  "https://github.com/superbrothers/zsh-kubectl-prompt.git|${ZSH_CUSTOM}/plugins/zsh-kubectl-prompt"
)
for _pair in "${_plugins[@]}"; do
  IFS='|' read -r _url _dest <<<"$_pair"
  [ -d "$_dest" ] || git clone --depth 1 "$_url" "$_dest"
done
unset _pair _url _dest _plugins

# Install YQ if its not already
VERSION=v4.44.1
BINARY=yq_linux_amd64
if [ ! -f /usr/bin/yq ]; then
    wget -T 30 --tries=3 -q "https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz" -O - | tar xz && sudo mv ${BINARY} /usr/bin/yq
fi
rm -f yq.1 install-man-page.sh

# Flux Operator CLI + flux-operator-mcp (pin to match cluster charts; override via FLUX_OPERATOR_TOOLS_VERSION)
FLUX_OPERATOR_TOOLS_VERSION="${FLUX_OPERATOR_TOOLS_VERSION:-v0.45.1}"
FO_VER="${FLUX_OPERATOR_TOOLS_VERSION#v}"
case "$(uname -m)" in
  x86_64) FO_ARCH=amd64 ;;
  aarch64) FO_ARCH=arm64 ;;
  *)
    echo "Skipping flux-operator tools install: unsupported arch $(uname -m)"
    FO_ARCH=""
    ;;
esac
if [ -n "$FO_ARCH" ]; then
  FO_BASE="https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/${FLUX_OPERATOR_TOOLS_VERSION}"
  if [ ! -f /usr/local/bin/flux-operator ]; then
    echo "Installing flux-operator ${FLUX_OPERATOR_TOOLS_VERSION} (${FO_ARCH})"
    curl -fsSL --connect-timeout 15 --max-time 120 "${FO_BASE}/flux-operator_${FO_VER}_linux_${FO_ARCH}.tar.gz" | tar xz -C /tmp
    sudo install -m 0755 "/tmp/flux-operator" /usr/local/bin/flux-operator
    rm -f "/tmp/flux-operator"
  fi
  if [ ! -f /usr/local/bin/flux-operator-mcp ]; then
    echo "Installing flux-operator-mcp ${FLUX_OPERATOR_TOOLS_VERSION} (${FO_ARCH})"
    curl -fsSL --connect-timeout 15 --max-time 120 "${FO_BASE}/flux-operator-mcp_${FO_VER}_linux_${FO_ARCH}.tar.gz" | tar xz -C /tmp
    sudo install -m 0755 "/tmp/flux-operator-mcp" /usr/local/bin/flux-operator-mcp
    rm -f "/tmp/flux-operator-mcp"
  fi
fi
