#!/bin/bash
#SBATCH --output=logs/%j-my_job.out

# Parse command line arguments
for i in "$@"
do
case $i in
    --docker-image=*)
    DOCKER_IMAGE="${i#*=}"
    shift
    ;;
    --docker-cmd=*)
    DOCKER_COMMAND="${i#*=}"
    shift
    ;;
    *)
    # unknown option
    usage
    ;;
esac
done

####################### Setup Docker Daemon #######################
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

####################### Run Docker Command #######################
docker pull $DOCKER_IMAGE

echo "Running command: docker run --rm $DOCKER_IMAGE $DOCKER_COMMAND" 
docker run --rm $DOCKER_IMAGE $DOCKER_COMMAND
