echo "Getting secrets"

echo "Making directory: ~/.ssh/"
mkdir -p ~/.ssh/

echo "Getting private key from 1 password"
op item get "Elderwand SSH Key" --vault Homelab --reveal --format json | jq -r '.fields[] | select(.label == "notesPlain") | .value' > ~/.ssh/id_rsa
op item get "Elderwand SSH Key" --vault Homelab --reveal --format json | jq -r '.fields[] | select(.label == "public_key") | .value' > ~/.ssh/id_rsa.pub

chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

echo "Done."

