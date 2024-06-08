#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

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
prompt_input DOCKER_IMAGE "Enter the docker image you want to use: "
prompt_input DOCKER_COMMAND "Enter the docker command you want to run: "

# Use default values if no input is provided
NUMER_OF_CPUS=${NUMER_OF_CPUS:-16}
MEMORY=${MEMORY:-64G}
VRAM=${VRAM:-10240}
USAGE_TIME=${USAGE_TIME:-"4:00:00"}
TMP_DISK_SIZE=${TMP_DISK_SIZE:-10240}

# Set PARTITION based on the day value
PARTITION="compute"
if [[ $USAGE_TIME == *-* ]]; then
    DAYS=${USAGE_TIME%%-*}
    if [ "$DAYS" -ge 1 ]; then
        PARTITION="compute_dense"
    fi
fi

# YOU CAN CHANGE THESE VALUES DIRECTLY IF YOU WANT TO
DOCKER_IMAGE=${DOCKER_IMAGE:-"nvidia/cuda:12.0.0-devel-ubuntu22.04"} # link to the image in the Docker Registry
DOCKER_COMMAND=${DOCKER_COMMAND:-"echo 'hello world in slurm job'"} # command to run inside the container

# Run a SLURM Batch Job
sbatch --cpus-per-task $NUMER_OF_CPUS --mem $MEMORY \
    --gres shard:$VRAM,tmpdisk:$TMP_DISK_SIZE --time $USAGE_TIME \
    $SCRIPT_DIR/../slurm_configurations/job_node_docker.slurm \
    --docker-image=$DOCKER_IMAGE --docker-cmd="$DOCKER_COMMAND"
