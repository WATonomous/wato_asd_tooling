########### Session Config ###########
# Configuration parameters used to   #
# start an interactive SLURM session #
######################################

# Variables for SSH and remote execution
export REMOTE_USER="rijul_chaddha"    # Your WATcloud Username
export REMOTE_HOST="wato-login1"      # [wato-login1, wato-login2]
export SSH_KEY="~/.ssh/id_ed25519"           # Path to your local private key

# SLURM job configuration
export NUMBER_OF_CPUS=8        # Number of CPUs to use
export MEMORY=64G              # Amount of RAM to use
export USAGE_TIME="6:00:00"    # How long you want to run the session for
export TMP_DISK_SIZE=102400     # How much temporary storage you want [in MiB]
export VRAM=24000                  # How much GPU VRAM you want [in MiB]
# SLURM tooling configuration
export UPDATE_WATO_ASD_TOOLING=0 # Set to 0 if you don't want to update ASD tooling on remote hosts
export SAVE_DOCKER_STATE_ON_EXIT=1 # Set to 1 if you want to save docker state on exit
export CLEAN_SAVED_DOCKER_STATE=0 # Set to 1 to clean your docker state, do this is your docker is corrupted or too large
