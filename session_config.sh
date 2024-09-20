########### Session Config ###########
# Configuration parameters used to   #
# start an interactive SLURM session #
######################################

# Variables for SSH and remote execution
export REMOTE_USER="j257jian"    # Your WATcloud Username
export REMOTE_HOST="tr-ubuntu3"      # [tr-ubuntu3, derek3-ubuntu2]
export SSH_KEY="~/.ssh/WATO_rsa"           # Path to your local private key

# SLURM job configuration
export NUMBER_OF_CPUS=4         # Number of CPUs to use
export MEMORY=16G              # Amount of RAM to use
export USAGE_TIME="6:00:00"    # How long you want to run the session for
export TMP_DISK_SIZE=40960     # How much temporary storage you want [in MiB]
export VRAM=0                  # How much GPU VRAM you want [in MiB]
