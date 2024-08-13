echo "Make git trust workspace directory"
if [ -d "/workspaces/home-kubernetes-docker" ]; then
    git config --global --add safe.directory /workspaces/home-kubernetes-docker
fi


echo "Creating project aliases"
cp scripts/files/aliases.zsh ~/.oh-my-zsh/custom/home-kubernetes-aliases.zsh

echo "Setting up starship"
cp scripts/files/starship.toml ~/.config/starship.toml
