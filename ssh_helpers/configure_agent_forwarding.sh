#!/bin/bash

# Colors and Utils
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../tooling_utils/colors.sh"
source "$SCRIPT_DIR/../tooling_utils/utils.sh"

# Check if we are running this script on WATcloud (not allowed)
terminate_on_watcloud_host

# Start an SSH agent if it's not already running
if [[ -z "$SSH_AUTH_SOCK" ]]; then
    echo -e "${YELLOW}Starting SSH agent...${NC}"
    eval "$(ssh-agent -s)"
else
    echo -e "${YELLOW}SSH agent is already running.${NC}"
fi

# Prompt the user for the SSH key path
read -p "Enter the SSH key path (default: ~/.ssh/id_rsa): " ssh_key_path

# Use the default path if no input is provided
if [[ -z "$ssh_key_path" ]]; then
    ssh_key_path="~/.ssh/id_rsa"
fi

# Resolve the path to the SSH key
resolved_ssh_key_path=$(eval echo $ssh_key_path)

# Check if the SSH key is already added to the agent
if ssh-add -l | grep -q "$(ssh-keygen -lf $resolved_ssh_key_path | awk '{print $2}')"; then
    echo -e "${YELLOW}The SSH key is already added to the agent.${NC}"
else
    # Add the SSH key to the agent
    echo -e "${YELLOW}Adding SSH key to the agent...${NC}"
    # Check if the system is a MacBook
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ssh-add --apple-use-keychain $resolved_ssh_key_path
    else
        ssh-add $resolved_ssh_key_path
    fi
    echo -e "${YELLOW}SSH key added to the agent.${NC}"
fi
