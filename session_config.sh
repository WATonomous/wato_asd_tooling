########### Session Config ###########
# Configuration parameters used to   #
# start an interactive SLURM session #
######################################

# Variables for SSH and remote execution
# REMOTE_USER="your_watcloud_username"
# REMOTE_HOST="watcloud_remote_host" # [tr-ubuntu3, derek3-ubuntu2]
# SSH_KEY="path_to_private_key"

REMOTE_USER="eddyzhou"
REMOTE_HOST="derek3-ubuntu2" # [tr-ubuntu3, derek3-ubuntu2]
SSH_KEY="~/.ssh/id_rsa"

# SLURM job configuration
NUMER_OF_CPUS=4
MEMORY=16G
USAGE_TIME="6:00:00"
TMP_DISK_SIZE=10240
VRAM=0
