########### Session Config ###########
# Configuration parameters used to   #
# start an interactive SLURM session #
######################################

# Variables for SSH and remote execution
export REMOTE_USER="your_watcloud_username"    # Your WATcloud Username
export REMOTE_HOST="watcloud_remote_host"      # [tr-ubuntu3, derek3-ubuntu2]
export SSH_KEY="path_to_private_key"           # Path to your local private key

# SLURM job configuration
export NUMBER_OF_CPUS=4         # Number of CPUs to use
export MEMORY=16G              # Amount of RAM to use
export USAGE_TIME="6:00:00"    # How long you want to run the session for
export TMP_DISK_SIZE=10240     # How much temporary storage you want [in MiB]
export VRAM=0                  # How much GPU VRAM you want [in MiB]
