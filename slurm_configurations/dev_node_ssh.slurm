#!/bin/bash

# Colors
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../tooling_utils/colors.sh"

####################### Notify User of Startup #######################
echo -e "${YELLOW}[NOTICE] SLURM JOB STARTING WITH JOB_ID ${SLURM_JOB_ID}. To connect to it through the terminal, use:"
echo -e ""
echo -e "srun --pty --overlap --jobid ${SLURM_JOB_ID} bash"
echo -e "${NC}"

####################### Setup Docker Daemon #######################
# Fuse user's docker filesystem if it exists
if [ -f $FILE_PATH ] && blkid $FILE_PATH &> /dev/null; then
  if [ ! -d "/tmp/docker" ]; then
    mkdir -p "/tmp/docker"
    echo "Directory created: /tmp/docker"
  fi
  fuse2fs -o nonempty -o fakeroot /mnt/wato-drive2/docker_filesystems/$USER/$USER.img /tmp/docker
fi

# Startup docker daemon
set -o pipefail -o errexit -o nounset

__orig_docker_host="${DOCKER_HOST:-}"

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/run}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/tmp/config}
export DOCKER_DATA_ROOT=${DOCKER_DATA_ROOT:-/tmp/docker}
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
export DOCKERD_CONFIG_FILE=${DOCKERD_CONFIG_FILE:-"/etc/docker/daemon.json"}

__dockerd_log_file="/tmp/dockerd.log"

mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"

echo "Starting dockerd. Data root: '${DOCKER_DATA_ROOT}'. Log file: '${__dockerd_log_file}'"

# --exec-opt native.cgroupdriver=cgroupfs is required because we don't have systemd
/usr/bin/dockerd-rootless.sh --data-root "${DOCKER_DATA_ROOT}" --exec-opt native.cgroupdriver=cgroupfs --config-file "${DOCKERD_CONFIG_FILE}" > "$__dockerd_log_file" 2>&1 &

__count=0

while ! docker ps > /dev/null 2>&1; do
    if [ $__count -gt 15 ]; then
        echo "Dockerd still not started after $__count seconds. Printing the logs from $__dockerd_log_file and exiting..."
        cat $__dockerd_log_file
        exit 1
    fi

    __count=$((__count+1))

    echo "Waiting for dockerd to start..."
    sleep 1
done

####################### Start SSH Daemon #######################
# Define the key file path
KEY_PATH="$HOME/.ssh/slurm_key"

# Check if the key file exists
if [ -f "$KEY_PATH" ]; then
    echo "Key file $KEY_PATH already exists."
else
    echo "Key file $KEY_PATH does not exist. Generating a new key pair..."
    
    # Generate a new SSH key pair
    ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N ""
    
    if [ $? -eq 0 ]; then
        echo "Key pair generated successfully."
    else
        echo "Failed to generate key pair."
        exit 1
    fi
fi

# This is the same base port calculation used in the monorepo
BASE_PORT=$(($(id -u)*20))
SSH_PORT=$((BASE_PORT--))

/usr/sbin/sshd -D -p $SSH_PORT -f /dev/null -h $KEY_PATH
