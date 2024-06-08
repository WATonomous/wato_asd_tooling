# utils.sh

# Source the color values
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/colors.sh"

# Check if we are running this script on WATcloud (not allowed)
terminate_on_watcloud_host() {
    local current_host=$(hostname)
    local hosts=("delta-ubuntu2" "derek3-ubuntu2" "tr-ubuntu3")
    for host in "${hosts[@]}"; do
        if [[ "$current_host" == "$host" ]]; then
            echo -e "${RED}[ERROR] You are currently running this script on one of the listed hosts (${hosts[@]}).${NC}"
            echo "Please run this script outside of WATcloud and on a computer that you want to use to connect to WATcloud."
            exit 1
        fi
    done
}