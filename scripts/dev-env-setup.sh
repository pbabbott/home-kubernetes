echo "Make git trust workspace directory"
if [ -d "/workspaces/home-kubernetes-docker" ]; then
    git config --global --add safe.directory /workspaces/home-kubernetes-docker
fi

echo "Creating project aliases"
cp scripts/files/aliases.zsh ~/.oh-my-zsh/custom/home-kubernetes-aliases.zsh

echo "Setting up starship"
cp scripts/files/starship.toml ~/.config/starship.toml

echo "Fetching oh-my-zsh plugins"
# TODO: wrap each one of these with a directory check
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git $ZSH_CUSTOM/plugins/you-should-use
git clone https://github.com/superbrothers/zsh-kubectl-prompt.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-kubectl-prompt

echo "Overwriting .zshrc file"
cp scripts/files/.zshrc ~/.zshrc