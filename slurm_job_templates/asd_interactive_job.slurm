#!/bin/bash

if [ -z "${SLURM_JOB_ID:-}" ]; then
    1>&2 echo "This script is meant to be run from within a Slurm job. We are not in a Slurm job. Exiting..."
    exit 1
fi

SIGINT_COUNT=0

cleanup() {
    SIGINT_COUNT=$((SIGINT_COUNT + 1))
    echo "Ctrl+C detected. Exiting gracefully...(press Ctrl+C again to force)"

    if [ "$SIGINT_COUNT" -gt 1 ]; then
        echo "Second Ctrl+C detected. Exiting forcefully."
        exit 1  
    fi
    
    exit 0
}

trap cleanup SIGINT

# Load docker session if exists, create file in wato-drive2 otherwise
DOCKER_SESSION_DIR="/mnt/wato-drive2/slurm-docker-sessions/$(id -u)/"
DOCKER_STATE_FILE="slurm-docker-state.tar.zst"
DOCKER_STATE_PATH="${DOCKER_SESSION_DIR}/${DOCKER_STATE_FILE}"

# Function to handle Docker state save
save_docker_state() {
    echo -e "Saving docker state..."
    if [[ ! -d "/tmp/docker" || ! -d "/tmp/run" || ! -d "$DOCKER_SESSION_DIR" ]]; then
        echo -e "One or more required directories do not exist. Exiting without saving."
        exit 1
    fi

    # Save the state using tar and compress with zstd
    if rootlesskit tar -cf - /tmp/docker /tmp/run | pzstd | pv > "$DOCKER_STATE_PATH"; then
        echo -e "Docker state saved successfully."
    else
        echo -e "Failed to save Docker state."
    fi
}

if [[ -f "$DOCKER_STATE_PATH" ]]; then
    echo "Saved docker state found. Loading..."
    zstd --fast=3 -d "$DOCKER_STATE_PATH" --stdout | pv | rootlesskit tar --blocking-factor=64 -xpf - -C /
else
    echo "Docker state file not found. Initializing directory to store docker state file."
    mkdir -p "$DOCKER_SESSION_DIR"
    chmod 700 "$DOCKER_SESSION_DIR"
    echo -e "Docker state directory initialized."
fi

####################### Notify User of Startup #######################
echo -e "\033[0;33m[NOTICE] SLURM JOB STARTING WITH JOB_ID ${SLURM_JOB_ID}. To connect to it through the terminal, use:"
echo -e ""
echo -e "srun --pty --overlap --jobid ${SLURM_JOB_ID} bash"
echo -e "\033[0m"

####################### Setup Docker Daemon #######################
bash "/opt/slurm/bin/slurm-start-dockerd.sh"

####################### Start SSH Daemon #######################
# Define the key file path
KEY_PATH="$HOME/.ssh/slurm_key"

# Check if the key file exists
if [ -f "$KEY_PATH" ]; then
    echo "Key file $KEY_PATH already exists."
else
    echo "Key file $KEY_PATH does not exist. Generating a new key pair..."
    
    # Generate a new SSH key pair
    ssh-keygen -t rsa -f "$KEY_PATH" -N ""
    
    if [ $? -eq 0 ]; then
        echo "Key pair generated successfully."
    else
        echo "Failed to generate key pair."
        exit 1
    fi
fi

# This is the same base port calculation used in the monorepo
BASE_PORT=$(($(id -u)*20))
SSH_PORT=$(($BASE_PORT - 1))

/usr/sbin/sshd -D -p $SSH_PORT -f /dev/null -h $KEY_PATH &

####################### Periodically Save Docker State #######################
# Set the interval (e.g., 900 seconds = 15 minutes)
INTERVAL=900

while true; do
    sleep $INTERVAL
    save_docker_state
done
