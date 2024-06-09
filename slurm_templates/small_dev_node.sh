#!/bin/bash

# Build your own computer! (SLURM Node)
NUMER_OF_CPUS=4
MEMORY=16G
USAGE_TIME="6:00:00"
TMP_DISK_SIZE=10240

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../slurm_helpers/setup_docker_filesystem.sh"

# Install Docker filesystem if needed
check_docker_filesystem_exists
if [ "$?" -eq 1 ]; then
    setup_docker_filesystem
fi

# Run SLURM
export LOGIN_NODE_NAME=$HOSTNAME
srun --cpus-per-task $NUMER_OF_CPUS --mem $MEMORY \
    --gres tmpdisk:$TMP_DISK_SIZE --time $USAGE_TIME \
    --pty bash "$SCRIPT_DIR/../slurm_configurations/dev_node_vscode.slurm"
