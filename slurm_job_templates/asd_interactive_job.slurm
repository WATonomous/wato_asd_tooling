#!/bin/bash

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

/usr/sbin/sshd -D -p $SSH_PORT -f /dev/null -h $KEY_PATH
