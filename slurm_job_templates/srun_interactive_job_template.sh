#!/bin/bash

sed -i 's/\r$//' $REMOTE_SLURM_JOB_SCRIPT

export SAVE_DOCKER_STATE_ON_EXIT=${SAVE_DOCKER_STATE_ON_EXIT}

# Run srun command
/opt/slurm/bin/srun --cpus-per-task=${NUMBER_OF_CPUS} --mem=${MEMORY} \
    --gres=tmpdisk:${TMP_DISK_SIZE},shard=${VRAM} --time=${USAGE_TIME} --job-name=wato_slurm_dev \
    --pty bash ~/slurm_tooling/asd_interactive_job.slurm
