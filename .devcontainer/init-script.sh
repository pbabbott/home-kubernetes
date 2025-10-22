echo "Make git trust workspace directory"
if [ -d "/workspaces/home-kubernetes-docker" ]; then
    git config --global --add safe.directory /workspaces/home-kubernetes-docker
fi

# Set up git origin to resolve push warning
git config --global push.autoSetupRemote true

# Set up git credential helper
git config --global credential.helper store

echo "pwd"
pwd

echo "Creating project aliases"
cp .devcontainer/files/aliases.zsh /home/vscode/.oh-my-zsh/custom/home-kubernetes-aliases.zsh

echo "Setting up starship"
cp .devcontainer/files/starship.toml /home/vscode/.config/starship.toml

echo "Fetching oh-my-zsh plugins"
# TODO: wrap each one of these with a directory check
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git $ZSH_CUSTOM/plugins/you-should-use
git clone https://github.com/superbrothers/zsh-kubectl-prompt.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-kubectl-prompt

echo "Overwriting .zshrc file"
cp .devcontainer/files/.zshrc /home/vscode/.zshrc

# Install YQ if its not already
VERSION=v4.44.1
BINARY=yq_linux_amd64

# TODO: install yq in devcontainer
if [ ! -f /usr/bin/yq ]; then
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - | tar xz && sudo mv ${BINARY} /usr/bin/yq
fi

# Clean up yq junk
rm yq.1
rm install-man-page.sh