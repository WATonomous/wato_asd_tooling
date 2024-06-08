#!/bin/bash

# Color Definitions
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Do not run this on WATcloud Machines
current_host=$(hostname)
hosts=("delta-ubuntu2" "derek3-ubuntu2" "tr-ubuntu3")
for host in "${hosts[@]}"; do
    if [[ "$current_host" == "$host" ]]; then
        echo -e "${RED}[ERROR] You are currently running this script on one of the listed hosts (${hosts[@]}).${NC}"
        echo "Please run this script outside of WATcloud and on a computer that you want to use to connect to WATcloud."
        exit 1
    fi
done

# Proceed with SSH Configuration generation
read -p "Enter the username: " username
read -p "Enter the SSH private key path (e.g., ~/.ssh/id_rsa): " ssh_key_path

# Generate the SSH configuration
ssh_config="Host delta-ubuntu2 derek3-ubuntu2 tr-ubuntu3
    Hostname %h.cluster.watonomous.ca
    User $username
    ForwardAgent Yes
    ProxyJump $username@bastion.watonomous.ca
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
    if grep -q -e "Host delta-ubuntu2" -e "Host derek3-ubuntu2" -e "Host tr-ubuntu3" ~/.ssh/config; then
        echo -e "${RED}[ERROR] One or more of the Hosts (delta-ubuntu2, derek3-ubuntu2, tr-ubuntu3) already exist in ~/.ssh/config."
        echo "Please delete all old WATO Hosts before proceeding.${NC}"
    else
        # Append the configuration to ~/.ssh/config
        echo "$ssh_config" >> ~/.ssh/config
        echo "Configuration appended to c"
    fi
else
    echo "Configuration not appended. Please copy the configuration and add it to your echo ~/.ssh/config."
fi
