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

####################### Startup VSCode Tunnel #######################
curl --silent --location 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' | tar -xzv 
./code tunnel --name slurm-${SLURM_JOB_ID}
