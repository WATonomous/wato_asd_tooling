#!/bin/bash
# Replaced by ./setup.sh; kept so that old instructions keep working.
set -o errexit -o nounset -o pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
echo "ssh_helpers/setup_slurm_ssh.sh is replaced by ./setup.sh; running it now. See README.md." >&2
exec "$DIR/setup.sh" "$@"
