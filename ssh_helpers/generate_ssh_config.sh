#!/bin/bash

# Colors and Utils
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../tooling_utils/colors.sh"
source "$SCRIPT_DIR/../tooling_utils/utils.sh"
source "$SCRIPT_DIR/../tooling_utils/watcloud_hosts.sh"

# Check if we are running this script on WATcloud (not allowed)
terminate_on_watcloud_host

# Proceed with SSH Configuration generation
read -p "Enter your WATcloud computer cluster username: " username
read -p "Enter your SSH private key path (e.g. ~/.ssh/id_rsa): " ssh_key_path

# Generate the SSH configuration
ssh_config="Host ${WATCLOUD_HOSTS[@]}
    Hostname %h.ext.watonomous.ca
    User $username
    ForwardAgent Yes
    IdentityFile $ssh_key_path
    IdentitiesOnly Yes"

# Display SSH configuration
echo "The following is your generated SSH Config:"
echo ""
echo -e "${YELLOW}$ssh_config${NC}"
echo ""

# Prompt the user to append the configuration to ~/.ssh/config
read -p "Would you like to append this configuration to ~/.ssh/config? (y/n): " append_choice

if [[ $append_choice == "y" || $append_choice == "Y" ]]; then
    # Check if the Hosts already exist in the ~/.ssh/config
    for host in "${WATCLOUD_HOSTS[@]}"; do
        if grep -q -e "Host ${host}" ~/.ssh/config; then
            echo -e "${RED}[ERROR] One or more of the Hosts (${WATCLOUD_HOSTS[@]}) already exist in ~/.ssh/config."
            echo -e "Please delete all old WATO Hosts before proceeding.${NC}"
            exit 1
        fi
    done
    
    # Append the configuration to ~/.ssh/config
    echo -e "\n$ssh_config" >> ~/.ssh/config
    echo "Configuration appended to ~/.ssh/config."
else
    echo "Configuration not appended. Please copy the configuration and add it to your ~/.ssh/config."
fi
