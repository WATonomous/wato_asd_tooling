#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/session_config.sh"

UPDATE_WATO_ASD_TOOLING=${UPDATE_WATO_ASD_TOOLING:-""}

export REMOTE_SLURM_DIR="~/slurm_tooling"
export REMOTE_SLURM_JOB_SCRIPT="$REMOTE_SLURM_DIR/asd_interactive_job.slurm"
export LOCAL_SLURM_JOB_SCRIPT="$SCRIPT_DIR/slurm_job_templates/asd_interactive_job.slurm"
export REMOTE_JOB_LAUNCH_SCRIPT="$REMOTE_SLURM_DIR/srun_interactive_job.sh"
export LOCAL_JOB_LAUNCH_TEMPLATE="$SCRIPT_DIR/slurm_job_templates/srun_interactive_job_template.sh"

# Check if the slurm_tooling directory exists and create it if necessary, and check if the file exists
ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_HOST << EOF
#!/bin/bash
if [ ! -d $REMOTE_SLURM_DIR ]; then
    echo "Directory $REMOTE_SLURM_DIR does not exist. Creating it..."
    mkdir -p $REMOTE_SLURM_DIR
else
    echo "Directory $REMOTE_SLURM_DIR already exists."
fi

if [ ! -f $REMOTE_SLURM_JOB_SCRIPT ] || [ ! -f $REMOTE_JOB_LAUNCH_SCRIPT ]; then
    echo "Required files do not exist on the remote machine. Ready to copy from local."
    exit 1  # File(s) not found
else
    echo "Files already exist on the remote machine."
    exit 0  # Required files exist
fi
EOF

# Check the exit status of the previous command
# UPDATE_WATO_ASD_TOOLING is an optionally set env var to be exported by the user
if [ $? -eq 1 ] || [ "$UPDATE_WATO_ASD_TOOLING" -eq 1 ]; then
    echo "Copying asd_interactive_job.slurm to the remote machine..."
    scp -p -i "$SSH_KEY" "$LOCAL_SLURM_JOB_SCRIPT" "$REMOTE_USER@$REMOTE_HOST:~/slurm_tooling/"
    
    echo "Copying the launch script to the remote machine..."
    TMP_JOB_LAUNCH_SCRIPT=$(mktemp)
    chmod +x "$TMP_JOB_LAUNCH_SCRIPT"
    envsubst < "$LOCAL_JOB_LAUNCH_TEMPLATE" > "$TMP_JOB_LAUNCH_SCRIPT"
    scp -p -i "$SSH_KEY" "$TMP_JOB_LAUNCH_SCRIPT" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_JOB_LAUNCH_SCRIPT"
fi

ssh -t -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "$REMOTE_JOB_LAUNCH_SCRIPT"
