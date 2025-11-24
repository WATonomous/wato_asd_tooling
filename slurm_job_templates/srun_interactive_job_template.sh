#!/bin/bash

sed -i 's/\r$//' $REMOTE_SLURM_JOB_SCRIPT

export SAVE_DOCKER_STATE_ON_EXIT=${SAVE_DOCKER_STATE_ON_EXIT}
export CLEAN_SAVED_DOCKER_STATE=${CLEAN_SAVED_DOCKER_STATE}

# Build the GRES string based on whether GPU_TYPE is specified
if [ -n "${GPU_TYPE}" ] && [ "${GPU_TYPE}" != "" ]; then
    GRES_ARG="tmpdisk:${TMP_DISK_SIZE},shard:${GPU_TYPE}:${VRAM}"
else
    GRES_ARG="tmpdisk:${TMP_DISK_SIZE},shard=${VRAM}"
fi

# Run srun command
/opt/slurm/bin/srun --cpus-per-task=${NUMBER_OF_CPUS} --mem=${MEMORY} \
    --gres=${GRES_ARG} --time=${USAGE_TIME} --job-name=wato_slurm_dev \
    --pty bash ~/slurm_tooling/asd_interactive_job.slurm