#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../tooling_utils/colors.sh"

# Define the key file path
KEY_PATH="$HOME/.ssh/slurm_key.pub"
JOB_NAME="wato_slurm_dev"

read -p "Enter your WATcloud username: " username
read -p "Enter your SSH private key path (e.g. ~/.ssh/id_rsa): " ssh_key_path

# Check if the key file exists, if not, copy from WATcloud
if [ -f "$KEY_PATH" ]; then
    echo "Key file $KEY_PATH already exists."
else
    echo "Key file $KEY_PATH does not exist. Copying your slurm key from the WATcloud server."
    scp $username@wato-login1:/home/$username/.ssh/slurm_key.pub $KEY_PATH
fi

# Generate SSH Config
echo "In order to create the configuration, we need your unique SSH_PORT on WATcloud."
echo "To find this, connect to one of the WATcloud servers and run:"
echo ""
echo " echo \$(( (\$(id -u)*20) - 1 )) "
echo ""
read -p "Enter Port Number Here: " ssh_port

# Generate the SSH configuration
ssh_config="Host asd-dev-session
    User $username
    ForwardAgent Yes
    PreferredAuthentications publickey
    PubkeyAuthentication yes
    IdentityFile $ssh_key_path
    ProxyCommand ssh wato-login1 \"nc \$(/opt/slurm/bin/squeue --user ${username} --name=wato_slurm_dev --states=R -h -O NodeList | awk '{print \$1;}').cluster.watonomous.ca ${ssh_port}\""

# Check if the system is either Linux or macOS
if [[ "$(uname)" == "Darwin" || "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
    echo -e "${YELLOW}OS is on Darwin or Linux, using a different ssh_config.${NC}"
    ssh_config="Host asd-dev-session
        User $username
        ForwardAgent Yes
        PreferredAuthentications publickey
        PubkeyAuthentication yes
        IdentityFile $ssh_key_path
        ProxyCommand ssh wato-login1 \"nc \\\$(/opt/slurm/bin/squeue --user ${username} --name=wato_slurm_dev --states=R -h -O NodeList | awk '{print \\\$1;}').cluster.watonomous.ca ${ssh_port}\""
fi

# Display SSH configuration
echo "The following is your generated SSH Config:"
echo ""
echo -e "${YELLOW}$ssh_config${NC}"
echo ""

# Prompt the user to append the configuration to ~/.ssh/config
read -p "Would you like to append this configuration to ~/.ssh/config? (y/n): " append_choice

if [[ $append_choice == "y" || $append_choice == "Y" ]]; then
    # Check if the Hosts already exist in the ~/.ssh/config
    if grep -q -e "Host asd-dev-session" ~/.ssh/config; then
        echo -e "${RED}[ERROR] asd-dev-session already exist in ~/.ssh/config."
        echo -e "Please delete the asd-dev-session configuration before proceeding.${NC}"
        exit 1
    fi

    # Append the configuration to ~/.ssh/config
    echo "$ssh_config" >> ~/.ssh/config
    echo "Configuration appended to ~/.ssh/config."
else
    echo "Configuration not appended. Please copy the configuration and add it to your ~/.ssh/config."
fi
