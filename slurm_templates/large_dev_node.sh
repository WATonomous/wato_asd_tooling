#!/bin/bash

# Build your own computer! (SLURM Node)
NUMER_OF_CPUS=16
MEMORY=64G
VRAM=10240 # 10G of GPU VRAM
USAGE_TIME="3:00:00"
TMP_DISK_SIZE=10240

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../slurm_helpers/setup_docker_filesystem.sh"

# Install Docker filesystem if needed
if [ check_if_docker_filesystem_exists ]; then
    setup_docker_filesystem
fi

# Run SLURM
srun --cpus-per-task $NUMER_OF_CPUS --mem $MEMORY \
    --gres shard:$VRAM,tmpdisk:$TMP_DISK_SIZE --time $USAGE_TIME \
    --pty bash "$SCRIPT_DIR/../slurm_configurations/dev_node_ssh.slurm"