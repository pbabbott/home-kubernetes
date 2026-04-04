export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="robbyrussell"

plugins=(git zsh-autosuggestions you-should-use zsh-kubectl-prompt)

# istioctl via devcontainer feature ghcr.io/devcontainers-extra/features/asdf-package (before oh-my-zsh)
[ -f "$HOME/.asdf/asdf.sh" ] && . "$HOME/.asdf/asdf.sh"

source $ZSH/oh-my-zsh.sh
RPROMPT='%{$fg[blue]%}[$ZSH_KUBECTL_NAMESPACE]%{$reset_color%}'

[[ $commands[kubectl] ]] && source <(kubectl completion zsh)

DISABLE_AUTO_UPDATE=true
DISABLE_UPDATE_PROMPT=true

. <(flux completion zsh)

[[ $commands[flux-operator] ]] && . <(flux-operator completion zsh)

eval "$(starship init zsh)"