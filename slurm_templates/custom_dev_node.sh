#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../slurm_helpers/setup_docker_filesystem.sh"

# Function to prompt for user input and assign to variable
prompt_input() {
  local var_name=$1
  local prompt_message=$2
  read -p "$prompt_message" $var_name
}

# Prompt the user to fill out the fields
prompt_input NUMER_OF_CPUS "Enter the number of CPUs (default: 16): "
prompt_input MEMORY "Enter the memory size (default: 64G): "
prompt_input VRAM "Enter the GPU VRAM size (default: 10240): "
prompt_input USAGE_TIME "Enter the usage time (default: 4:00:00): "
prompt_input TMP_DISK_SIZE "Enter the temporary disk size (default: 10240): "

# Use default values if no input is provided
NUMER_OF_CPUS=${NUMER_OF_CPUS:-16}
MEMORY=${MEMORY:-64G}
VRAM=${VRAM:-10240}
USAGE_TIME=${USAGE_TIME:-"4:00:00"}
TMP_DISK_SIZE=${TMP_DISK_SIZE:-10240}

# Install Docker filesystem if needed
if [ check_if_docker_filesystem_exists ]; then
    setup_docker_filesystem
fi

# Run SLURM
srun --cpus-per-task $NUMER_OF_CPUS --mem $MEMORY \
    --gres shard:$VRAM,tmpdisk:$TMP_DISK_SIZE --time $USAGE_TIME \
    --pty bash "$SCRIPT_DIR/../slurm_configurations/dev_node_ssh.slurm"