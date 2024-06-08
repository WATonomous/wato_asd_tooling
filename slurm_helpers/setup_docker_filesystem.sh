# setup_docker_filesystem.sh

# Colors
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../../tooling_utils/colors.sh"

# Define the path and file name
FILE_PATH="/mnt/wato-drive2/docker_filesystems/$USER/$USER.img"

check_if_docker_filesystem_exists() {
  # Check if a filesystem already exists on the file
  if [ -f $FILE_PATH ] && blkid $FILE_PATH &> /dev/null; then
    echo "Filesystem already exists on: $FILE_PATH"
    echo "Exiting script to avoid overwriting existing filesystem."
    return 0
  fi

  return 1
}

setup_docker_filesystem() {
  # Prompt the user to append the configuration to ~/.ssh/config
  echo -e "${YELLOW}You are about to make a new docker filesystem as ${FILE_PATH}. This step is to let docker images persist between SLURM jobs. ${NC}"
  read -p "Do you wish to proceed? (y/n): " append_choice

  if [[ $append_choice == "y" || $append_choice == "Y" ]]; then
    # Create the directory if it doesn't exist
    DIR_PATH=$(dirname $FILE_PATH)
    if [ ! -d $DIR_PATH ]; then
      mkdir -p $DIR_PATH
      echo "Directory created: $DIR_PATH"
    fi

    # Create or truncate the file to 50GB
    truncate -s 50G $FILE_PATH
    echo "File truncated to 50GB: $FILE_PATH"

    # Format the file with ext4 filesystem
    mkfs.ext4 $FILE_PATH
    echo "Filesystem ext4 created on: $FILE_PATH"

    echo -e "${YELLOW}[NOTICE] If you do not use your docker system for a long time, we may delete it to save space."
    echo -e "Make sure to utilize a Docker Registry whenever you can."
  else
    echo -e "${RED}Docker Filesystem creation cancelled.${NC}"
  fi
}
