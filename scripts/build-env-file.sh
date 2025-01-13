#!/bin/bash

# Function to get a value from 1Password
get_note_value() {
    local item_name="$1"
    op item get "$item_name" --format json --vault Homelab | jq -r '.fields[] | select(.label == "notesPlain") | .value'
}

get_login_password() {
    local item_name="$1"
    op item get "$item_name" --format json --vault Homelab | jq -r '.fields[] | select(.id == "password") | .value'
}

get_login_username() {
    local item_name="$1"
    op item get "$item_name" --format json --vault Homelab | jq -r '.fields[] | select(.id == "username") | .value'
}

# Function to update a specific key in the .env file
update_env_key() {
    local env_file="$1"
    local key="$2"
    local new_value="$3"
    sed -i "s|^$key=.*|$key=$new_value|" "$env_file"
}

# Function to update all keys in the .env file
update_all_keys() {
    local env_file="$1"
    update_env_key "$env_file" "CLOUDFLARE_EMAIL" "$(get_login_username "Cloudflare")"
    update_env_key "$env_file" "CLOUDFLARE_TOKEN" "$(get_note_value "CLOUDFLARE_TOKEN")"
    
    update_env_key "$env_file" "DRONE_RPC_SECRET" "$(get_note_value "DRONE_RPC_SECRET")"
    update_env_key "$env_file" "DRONE_GITHUB_CLIENT_ID" "$(get_note_value "DRONE_GITHUB_CLIENT_ID")"
    update_env_key "$env_file" "DRONE_GITHUB_CLIENT_SECRET" "$(get_note_value "DRONE_GITHUB_CLIENT_SECRET")"
    update_env_key "$env_file" "DRONE_DATABASE_DATASOURCE" "$(get_note_value "DRONE_DATABASE_DATASOURCE")"

    update_env_key "$env_file" "HARBOR_ADMIN_PASSWORD" "$(get_login_password "harbor.local.abbottland.io - admin")"
    update_env_key "$env_file" "HARBOR_POSTGRES_PASSWORD" "$(get_note_value "HARBOR_POSTGRES_PASSWORD")"
    update_env_key "$env_file" "HARBOR_REG_EMAIL" "$(get_note_value "HARBOR_REG_EMAIL")"
    update_env_key "$env_file" "HARBOR_REG_USERNAME" "$(get_note_value "HARBOR_REG_USERNAME")"
    update_env_key "$env_file" "HARBOR_REG_PASSWORD" "$(get_login_password "harbor.local.abbottland.io - pbabbott")"
    
    update_env_key "$env_file" "OPENVPN_USER" "$(get_login_username "PrivateInternetAccess.com")"
    update_env_key "$env_file" "OPENVPN_PASSWORD" "$(get_login_password "PrivateInternetAccess.com")"

    update_env_key "$env_file" "QBITTORRENT_PASSWORD" "$(get_login_password "qbittorrent.local.abbottland.io - admin")"
}

# Usage
ENV_FILE='.env'
cp .env.sample .env
update_all_keys "$ENV_FILE"

# Example of updating a single key
# update_env_key "$ENV_FILE" "CLOUDFLARE_TOKEN" "$(get_op_value "Cloudflare" "API Token")"

