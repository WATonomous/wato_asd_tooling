#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/session_config.sh"

REMOTE_SLURM_DIR="~/slurm_tooling"
REMOTE_SLURM_FILE="$REMOTE_SLURM_DIR/asd_interactive_job.slurm"
LOCAL_SLURM_FILE="$SCRIPT_DIR/slurm_job_templates/asd_interactive_job.slurm"

# Check if the slurm_tooling directory exists and create it if necessary, and check if the file exists
ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST << EOF
#!/bin/bash
if [ ! -d $REMOTE_SLURM_DIR ]; then
    echo "Directory $REMOTE_SLURM_DIR does not exist. Creating it..."
    mkdir -p $REMOTE_SLURM_DIR
else
    echo "Directory $REMOTE_SLURM_DIR already exists."
fi

if [ ! -f $REMOTE_SLURM_FILE ]; then
    echo "File does not exist on the remote machine. Ready to copy from local."
    exit 1  # File not found
else
    echo "File already exists on the remote machine."
    exit 0  # File exists
fi
EOF

# Check the exit status of the previous command
if [ $? -eq 1  || UPDATE_REMOTE_FILES ]; then
    echo "Copying asd_interactive_job.slurm to the remote machine..."
    scp -i $SSH_KEY $LOCAL_SLURM_FILE $REMOTE_USER@$REMOTE_HOST:~/slurm_tooling/
    echo "coping the other thing too"
    scp -i THING
fi

# SSH command to run remote script
ssh -t -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" << EOF
#!/bin/bash

sed -i 's/\r$//' $REMOTE_SLURM_FILE

# Run srun command
srun --cpus-per-task=$NUMER_OF_CPUS --mem=$MEMORY \\
    --gres=tmpdisk:$TMP_DISK_SIZE,shard=$VRAM --time=$USAGE_TIME --job-name=wato_slurm_dev \\
    --pty bash ~/slurm_tooling/asd_interactive_job.slurm
EOF

# ssh -t HOST "~/some_script.sh"
