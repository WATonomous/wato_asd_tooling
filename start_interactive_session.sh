#!/bin/bash
# Replaced by ./setup.sh (once) and ./asd-dev start; kept so that old instructions keep working.
set -o errexit -o nounset -o pipefail
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "start_interactive_session.sh is replaced by ./setup.sh (once) and ./asd-dev start; see README.md." >&2
if ! ssh -G asd-dev-login 2>/dev/null | grep -q '^hostname wato-login'; then
    echo "Running ./setup.sh first (it reuses the username and key from session_config.sh)..." >&2
    "$DIR/setup.sh"
fi
exec "$DIR/asd-dev" start "$@"
