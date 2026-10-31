#!/usr/bin/env bash
# One-time setup: lets VS Code (and ssh) on this computer connect into a WATcloud SLURM session.
# For macOS, Linux, ChromeOS (Linux), WSL and Git Bash. On native Windows run setup.cmd instead.
# Usage: ./setup.sh [--user NAME] [--key PATH] ...   (./setup.sh --help)
#
# Runs on the macOS system bash 3.2: no associative arrays, no ${x,,}, guard empty arrays.
set -o errexit -o nounset -o pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER="$REPO_DIR/cluster/asd-dev"
BLOCK_BEGIN="# >>> asd-dev (wato_asd_tooling) >>>"
BLOCK_END="# <<< asd-dev (wato_asd_tooling) <<<"
PROFILE_URL="https://cloud.watonomous.ca/docs/utilities/profile-editor"
VPN_URL="https://uwaterloo.ca/information-systems-technology/services/virtual-private-network-vpn"

if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m' C_YEL=$'\033[0;33m' C_GRN=$'\033[0;32m' C_BOLD=$'\033[1m' C_OFF=$'\033[0m'
else
    C_RED="" C_YEL="" C_GRN="" C_BOLD="" C_OFF=""
fi
info() { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_OFF"; }
ok() { printf '%s%s%s\n' "$C_GRN" "$*" "$C_OFF"; }
warn() { printf '%sWARNING: %s%s\n' "$C_YEL" "$*" "$C_OFF" >&2; }
fail() {
    printf '\n%sERROR: %s%s\n' "$C_RED" "$1" "$C_OFF" >&2
    shift
    local line
    for line in "$@"; do printf '  %s\n' "$line" >&2; done
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Sets up this computer so that VS Code's "Remote - SSH" can connect to "asd-dev-session",
a dev session that runs inside a WATcloud SLURM job. Safe to run again at any time.

  --user NAME        your WATcloud compute cluster username (asked if omitted)
  --key PATH         private key registered with WATcloud (asked if omitted); a .pub file
                     works too when the private key only lives in an SSH agent (1Password etc.)
  --login HOST       wato-login1 (default) or wato-login2
  --ssh-config FILE  ssh config file to write (default: the one VS Code reads)
  --no-windows       on WSL: do not also configure Windows (where VS Code runs)
  --no-agent-forwarding  do not forward your SSH agent into sessions (it is forwarded by default so
                     git over SSH works there; root on the compute node could use it meanwhile)
  --add-session NAME only add the host asd-dev-session-NAME for a named session to the ssh config
                     (./asd-dev add --name NAME and ./asd-dev start --name NAME call this)
  --cluster-dir DIR  install the cluster helper in ~/DIR instead of ~/.asd-dev (for a second,
                     independent install, e.g. to test another version)
  --yes              do not ask questions; use defaults and the values given
  -h, --help         show this help

Defaults for new sessions (stored on the cluster in ~/.asd-dev/config; only the values given change):
  --cpus N --mem 16G --time 6:00:00 --tmpdisk MiB --vram MiB --gpus N --gpu-type TYPE
  --docker-state yes|no
EOF
}

# ---------------------------------------------------------------- arguments

ARG_USER="" ARG_KEY="" ARG_LOGIN="" ARG_CONFIG="" ARG_CLUSTER_DIR="" ARG_FORWARD="" ARG_ADD="" ASSUME_YES=no DO_WINDOWS=yes
CLUSTER_SETTINGS=()
add_setting() {
    [[ $2 =~ ^[A-Za-z0-9_:.-]*$ ]] || fail "invalid value for --$1: '$2'"
    CLUSTER_SETTINGS+=("$1=$2")
}
while (($#)); do
    case $1 in
        --user) ARG_USER=${2:?--user needs a value}; shift ;;
        --key) ARG_KEY=${2:?--key needs a value}; shift ;;
        --login) ARG_LOGIN=${2:?--login needs a value}; shift ;;
        --ssh-config) ARG_CONFIG=${2:?--ssh-config needs a value}; shift ;;
        --cluster-dir) ARG_CLUSTER_DIR=${2:?--cluster-dir needs a value}; shift ;;
        --add-session) ARG_ADD=$(printf '%s' "${2:?--add-session needs a name}" | tr '[:upper:]' '[:lower:]'); shift ;;
        --no-agent-forwarding) ARG_FORWARD=no ;;
        --agent-forwarding) ARG_FORWARD=yes ;;
        --no-windows) DO_WINDOWS=no ;;
        --yes | -y) ASSUME_YES=yes ;;
        --cpus | --mem | --time | --tmpdisk | --vram | --gpus | --gpu-type | --docker-state)
            key=${1#--}
            key=$(printf '%s' "$key" | tr '-' '_')
            add_setting "$key" "${2:?$1 needs a value}"
            shift
            ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; fail "unknown option '$1'" ;;
    esac
    shift
done

ask() { # ask VAR "question" "default"
    local __var=$1 __q=$2 __def=${3:-} __ans=""
    if [[ $ASSUME_YES == yes || ! -t 0 ]]; then
        __ans=$__def
    else
        if [[ -n $__def ]]; then read -r -p "$__q [$__def]: " __ans || true; else read -r -p "$__q: " __ans || true; fi
        __ans=${__ans:-$__def}
    fi
    printf -v "$__var" '%s' "$__ans"
}
confirm() { # confirm "question" (default yes)
    local ans=""
    [[ $ASSUME_YES == yes || ! -t 0 ]] && return 0
    read -r -p "$1 [Y/n]: " ans || true
    [[ -z $ans || $ans == [Yy]* ]]
}

# ---------------------------------------------------------------- environment

detect_env() {
    case $(uname -s) in
        Darwin) ENV_KIND=macos ;;
        Linux)
            if [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/version 2>/dev/null; then
                ENV_KIND=wsl
            elif [[ -e /dev/.cros_milestone || -d /opt/google/cros-containers ]]; then
                ENV_KIND=chromeos
            else
                ENV_KIND=linux
            fi
            ;;
        MINGW* | MSYS* | CYGWIN*) ENV_KIND=gitbash ;;
        *) ENV_KIND=unknown ;;
    esac
}

# The home directory ssh uses for "~": the passwd entry, which can differ from $HOME.
passwd_home() {
    local u h
    u=$(id -un)
    [[ $u =~ ^[A-Za-z0-9._-]+$ ]] || { printf '%s' "$HOME"; return; }
    h=$(eval "printf '%s' ~$u" 2>/dev/null || true)
    [[ -n $h && $h != "~$u" ]] && printf '%s' "$h" || printf '%s' "$HOME"
}

# Windows user profile as a path usable from this shell (WSL or Git Bash).
windows_profile() {
    local p=""
    if [[ $ENV_KIND == gitbash ]]; then
        [[ -n ${USERPROFILE:-} ]] && p=$(cygpath -u "$USERPROFILE")
    elif [[ $ENV_KIND == wsl ]]; then
        local cmd=cmd.exe
        command -v cmd.exe >/dev/null || cmd=/mnt/c/Windows/System32/cmd.exe
        p=$(cd /mnt/c 2>/dev/null && "$cmd" /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' || true)
        [[ -n $p && $p != *%* ]] && p=$(wslpath -u "$p" 2>/dev/null || true) || p=""
    fi
    printf '%s' "$p"
}

# Path in the form the ssh that reads the config understands.
native_path() { # native_path PATH windows|unix
    if [[ $2 == windows ]]; then
        if [[ $ENV_KIND == wsl ]]; then wslpath -m "$1"; else cygpath -m "$1"; fi
    else
        printf '%s' "$1"
    fi
}

# Compares two text files; cmp is missing on minimal Fedora and Arch images.
same_file() { [[ -f $1 && -f $2 ]] && [[ "$(cat "$1")" == "$(cat "$2")" ]]; }

ssh_quote() { # quotes a config value if needed
    if [[ $1 == *[[:space:]]* ]]; then printf '"%s"' "$1"; else printf '%s' "$1"; fi
}

# ---------------------------------------------------------------- the ssh config block

LOGIN_HOSTNAME=""
CLUSTER_USER=""
RC_NONE=""
CLUSTER_DIR=.asd-dev
FORWARD_AGENT=yes
SESSION_NAMES=""

# known_hosts name of the session host key: one per install, so installs sharing an ssh
# directory do not replace each other's key.
kh_alias() { if [[ $CLUSTER_DIR == .asd-dev ]]; then printf 'asd-dev-session'; else printf 'asd-dev-session@%s' "$CLUSTER_DIR"; fi; }

# make_block IDENTITY KNOWN_HOSTS PROXY_CONFIG(empty = default config)
make_block() {
    local identity known proxy_f=""
    identity=$(ssh_quote "$1")
    known=$(ssh_quote "$2")
    [[ -n $3 ]] && proxy_f=" -F $(ssh_quote "$3")"
    cat <<EOF
$BLOCK_BEGIN
# Written by wato_asd_tooling's setup. Run it again to change this block; edits here are lost.
# The login node, used as the hop; the "*" keeps VS Code from listing it (VS Code must not run there).
Host asd-dev-login*
    HostName $LOGIN_HOSTNAME
    User $CLUSTER_USER
    IdentityFile $identity
    IdentitiesOnly yes$RC_NONE
    UserKnownHostsFile $known
    StrictHostKeyChecking accept-new
    ConnectTimeout 10
    ForwardAgent no
    ServerAliveInterval 15
    ServerAliveCountMax 4

# One entry per session, each passing its own name as a fixed word: no host name that anyone
# types (a git submodule URL, say) reaches a shell, on any client. Add a named session with
# ./asd-dev add --name NAME (./asd-dev start --name NAME does it too).
EOF
    local n hosts="asd-dev-session"
    for n in default $SESSION_NAMES; do
        local alias=asd-dev-session
        [[ $n == default ]] || alias="asd-dev-session-$n"
        [[ $n == default ]] || hosts+=" $alias"
        printf 'Host %s\n    ProxyCommand ssh%s -T asd-dev-login %s/bin/asd-dev proxy %s%s\n' \
            "$alias" "$proxy_f" "$CLUSTER_DIR" "$alias" "$RC_NONE"
    done
    cat <<EOF
Host $hosts
    User $CLUSTER_USER
    IdentityFile $identity
    IdentitiesOnly yes
    HostKeyAlias $(kh_alias)
    UserKnownHostsFile $known
    StrictHostKeyChecking yes
    ForwardAgent $FORWARD_AGENT
    ServerAliveInterval 15
    ServerAliveCountMax 4

# Ends the block above so that settings below it keep applying to all hosts.
Host *
$BLOCK_END
EOF
}

# install_block CONFIG_FILE BLOCK_TEXT: puts the block at the top, replacing an older one.
install_block() {
    local config=$1 block=$2 dir tmp
    dir=$(dirname "$config")
    if [[ ! -d $dir ]]; then
        mkdir -p "$dir"
        chmod 700 "$dir"
    fi
    [[ -e $config ]] || { : >"$config"; chmod 600 "$config"; }
    tmp=$(mktemp "${TMPDIR:-/tmp}/asd-dev-config.XXXXXX")

    # Entries for our host names outside the block. The old setup_slurm_ssh.sh wrote one whose
    # ProxyCommand looks up wato_slurm_dev; only that one is offered for commenting out, and only
    # with the user's consent. A user's own entry is never changed (ours come first and win).
    # The awk scripts compare lines without a trailing CR, so CRLF files (Windows) work too.
    local entries
    entries=$(awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        { l = $0; sub(/\r$/, "", l) }
        l == b { inb = 1 } l == e { inb = 0; next }
        inb { next }
        tolower(l) ~ /^[ \t]*(host|match)[ \t=]/ {
            if (start) print start "|" old "|" line
            start = 0; old = 0
            if (tolower(l) ~ /^[ \t]*host[ \t=].*asd-dev-session/) { start = NR; line = l }
            next
        }
        start && l ~ /wato_slurm_dev/ { old = 1 }
        END { if (start) print start "|" old "|" line }' "$config")
    local disable="" n is_old line
    while IFS='|' read -r n is_old line; do
        [[ -n $n ]] || continue
        if [[ $is_old == 1 ]]; then
            warn "$config has an asd-dev-session entry from the previous tooling (line $n: $line)."
            if [[ -n $ARG_ADD ]]; then
                warn "left as it is; run ./setup.sh once to clean it up."
            elif [[ -t 0 && $ASSUME_YES != yes ]]; then
                if confirm "Comment it out so it does not interfere?"; then disable+=" $n"; fi
            elif [[ $ASSUME_YES == yes ]]; then
                info "  commenting it out (--yes)"
                disable+=" $n"
            else
                warn "left as it is (no terminal to ask); run setup in a terminal, or with --yes, to comment it out."
            fi
        else
            info "  your own entry '$line' (line $n) stays; the asd-dev entries come first, so theirs win."
        fi
    done <<<"$entries"

    {
        printf '%s\n\n' "$block"
        awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" -v disable="$disable " '
            { l = $0; sub(/\r$/, "", l) }
            l == b { inb = 1; next }
            inb { if (l == e) { inb = 0; skipblank = 1 } next }
            skipblank && l ~ /^[ \t]*$/ { next }
            { skipblank = 0 }
            tolower(l) ~ /^[ \t]*(host|match)[ \t=]/ { inlegacy = (index(disable, " " NR " ") > 0) }
            inlegacy { print "# [disabled by asd-dev setup] " $0; next }
            { print }' "$config"
    } >"$tmp"

    if same_file "$tmp" "$config"; then
        rm -f "$tmp"
        info "  $config is already up to date"
        return
    fi
    if [[ -s $config ]]; then
        local backup
        backup="$config.asd-dev-backup-$(date '+%Y%m%d-%H%M%S')"
        cp -p "$config" "$backup"
        info "  backed up the old file to $backup"
        # Keep the three newest backups.
        # shellcheck disable=SC2012 # names we created, newest first
        ls -t "$config".asd-dev-backup-* 2>/dev/null | tail -n +4 | while IFS= read -r old; do rm -f "$old"; done
    fi
    # Write in place: keeps a symlinked config (dotfile managers) and its permissions.
    cat "$tmp" >"$config"
    rm -f "$tmp"
    ok "  wrote the asd-dev entries at the top of $config"
}

# write_known_hosts FILE: keeps login node keys, replaces the session host key lines.
write_known_hosts() {
    local file=$1 tmp
    mkdir -p "$(dirname "$file")"
    tmp=$(mktemp "${TMPDIR:-/tmp}/asd-dev-kh.XXXXXX")
    local alias
    alias=$(kh_alias)
    [[ -f $file ]] && grep -v "^$alias " "$file" >"$tmp" || true
    printf '%s %s\n' "$alias" "$HOSTKEY" >>"$tmp"
    cat "$tmp" >"$file"
    chmod 600 "$file" 2>/dev/null || true
    rm -f "$tmp"
}

# ---------------------------------------------------------------- previous answers

previous_value() { # previous_value CONFIG KEYWORD: value from our block's asd-dev-login entry
    [[ -f $1 ]] || return 0
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" -v k="$2" '
        { sub(/\r$/, "") }
        $0 == b { inb = 1; next } $0 == e { inb = 0 }
        inb && tolower($1) == "host" { inlogin = ($2 ~ /^asd-dev-login/) }
        inb && inlogin && tolower($1) == k { $1 = ""; sub(/^ +/, ""); gsub(/"/, ""); print; exit }' "$1"
}

previous_forward_agent() { # ForwardAgent in our block's session entry
    [[ -f $1 ]] || return 0
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        { sub(/\r$/, "") }
        $0 == b { inb = 1; next } $0 == e { inb = 0 }
        inb && tolower($1) == "host" { insession = ($2 == "asd-dev-session") }
        inb && insession && tolower($1) == "forwardagent" { print tolower($2); exit }' "$1"
}

previous_cluster_dir() { # the helper dir in our block's ProxyCommand
    [[ -f $1 ]] || return 0
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        { sub(/\r$/, "") }
        $0 == b { inb = 1; next } $0 == e { inb = 0 }
        inb && tolower($1) == "proxycommand" {
            for (i = 2; i <= NF; i++) if ($i ~ /\/bin\/asd-dev$/) { sub(/\/bin\/asd-dev$/, "", $i); print $i; exit }
        }' "$1"
}

# Blocks written before the per-session entries pass %h, which a crafted host name could abuse.
has_old_layout() { grep -qE "asd-dev proxy ('%h'|%h)" "$1" 2>/dev/null; }

previous_sessions() { # names of the named sessions that have their own entry in our block
    [[ -f $1 ]] || return 0
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        { sub(/\r$/, "") }
        $0 == b { inb = 1; next } $0 == e { inb = 0 }
        inb && tolower($1) == "host" && NF == 2 && $2 ~ /^asd-dev-session-[a-z0-9][a-z0-9_-]*$/ {
            sub(/^asd-dev-session-/, "", $2); printf "%s ", $2 }' "$1"
}

previous_proxy_config() { # the -F file in our block's ProxyCommand, if any
    [[ -f $1 ]] || return 0
    local line
    line=$(awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        { sub(/\r$/, "") }
        $0 == b { inb = 1; next } $0 == e { inb = 0 }
        inb && tolower($1) == "proxycommand" { print; exit }' "$1")
    if [[ $line =~ -F\ \"([^\"]*)\" ]]; then printf '%s' "${BASH_REMATCH[1]}"
    elif [[ $line =~ -F\ ([^ ]+) ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi
}

# --add-session: rewrites the block of CONFIG with one more session, from the block's own values.
add_session_to() { # add_session_to CONFIG NAME
    local config=$1 name=$2 known proxy
    grep -q "^$BLOCK_BEGIN" "$config" 2>/dev/null || return 1
    if has_old_layout "$config"; then
        fail "$config has asd-dev entries from an earlier version (with %h)." \
            "Run ./setup.sh once (without --add-session); it keeps your settings and sessions."
    fi
    CLUSTER_USER=$(previous_value "$config" user)
    LOGIN_HOSTNAME=$(previous_value "$config" hostname)
    CLUSTER_DIR=$(previous_cluster_dir "$config")
    CLUSTER_DIR=${CLUSTER_DIR:-.asd-dev}
    FORWARD_AGENT=$(previous_forward_agent "$config")
    FORWARD_AGENT=${FORWARD_AGENT:-yes}
    known=$(previous_value "$config" userknownhostsfile)
    proxy=$(previous_proxy_config "$config")
    RC_NONE=""
    if awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '{ sub(/\r$/, "") } $0 == b { inb = 1 } $0 == e { inb = 0 }
        inb && tolower($1) == "remotecommand" { f = 1 } END { exit !f }' "$config"; then
        RC_NONE=$'\n    RemoteCommand none'
    fi
    SESSION_NAMES=$(previous_sessions "$config")
    [[ " $SESSION_NAMES " == *" $name "* ]] || SESSION_NAMES+=" $name"
    install_block "$config" "$(make_block "$(previous_value "$config" identityfile)" "$known" "$proxy")"
}

# ---------------------------------------------------------------- main

add_session_main() {
    local name=$ARG_ADD home config
    [[ $name =~ ^[a-z0-9][a-z0-9_-]{0,19}$ && $name != default ]] ||
        fail "invalid session name '$name'" "Use up to 20 lowercase letters, digits, '-' or '_'."
    home=$(passwd_home)
    [[ $ENV_KIND == gitbash ]] && home=$(windows_profile)
    config=${ARG_CONFIG:-"$home/.ssh/config"}
    add_session_to "$config" "$name" ||
        fail "$config has no asd-dev entries yet; run ./setup.sh first."
    if [[ $ENV_KIND == wsl && $DO_WINDOWS == yes ]]; then
        local wp
        wp=$(windows_profile)
        if [[ -n $wp ]] && add_session_to "$wp/.ssh/config" "$name"; then
            ok "  Windows: added asd-dev-session-$name too"
        fi
    fi
    ok "VS Code now lists asd-dev-session-$name (Remote Explorer > SSH)."
}

main() {
    detect_env
    if [[ -n $ARG_ADD ]]; then
        add_session_main
        return
    fi
    [[ -f $HELPER ]] || fail "missing $HELPER; run setup.sh from a complete clone of wato_asd_tooling."
    command -v ssh >/dev/null || fail "ssh is not installed." "Install OpenSSH (e.g. 'sudo apt install openssh-client') and run setup again."

    local home sshdir config proxy_f=""
    home=$(passwd_home)
    case $ENV_KIND in
        gitbash)
            local wp
            wp=$(windows_profile)
            [[ -n $wp ]] || fail "could not find your Windows user profile (USERPROFILE is not set)."
            home=$wp
            ;;
        unknown) warn "unrecognized system $(uname -s); continuing as if it were Linux." ;;
    esac
    sshdir="$home/.ssh"
    config=${ARG_CONFIG:-"$sshdir/config"}
    if [[ -n $ARG_CONFIG ]]; then
        local cdir
        cdir=$(cd "$(dirname "$ARG_CONFIG")" 2>/dev/null && pwd) ||
            fail "the directory of --ssh-config $ARG_CONFIG does not exist."
        config="$cdir/$(basename "$ARG_CONFIG")"
        sshdir=$(dirname "$config")
        [[ $config != "$home/.ssh/config" ]] && proxy_f=$config
    fi
    local known="$sshdir/asd-dev_known_hosts"

    info "${C_BOLD}wato_asd_tooling setup${C_OFF}: VS Code dev sessions in WATcloud SLURM jobs"
    info "This computer: $ENV_KIND. ssh config to write: $config"
    case $ENV_KIND in
        wsl) info "VS Code runs on Windows, not in WSL, so setup also configures Windows (skip with --no-windows)." ;;
        gitbash) info "VS Code uses Windows' own ssh; it reads the same $config." ;;
    esac

    # --- username
    step "Your cluster username"
    local def_user
    def_user=${ARG_USER:-$(previous_value "$config" user)}
    if [[ -z $ARG_USER ]]; then
        info "This is the 'Username' in the 'Compute Cluster' section of your WATcloud profile,"
        info "the name you use in 'ssh <username>@wato-login1.ext.watonomous.ca'. It can differ from"
        info "your WATcloud username. Look it up at $PROFILE_URL"
    fi
    ask CLUSTER_USER "Cluster username" "$def_user"
    # Accept "Name" and a pasted "name@wato-login1.ext.watonomous.ca".
    CLUSTER_USER=$(printf '%s' "$CLUSTER_USER" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    CLUSTER_USER=${CLUSTER_USER%%@*}
    [[ -n $CLUSTER_USER ]] || fail "a cluster username is required."
    [[ $CLUSTER_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
        fail "'$CLUSTER_USER' is not a valid cluster username (lowercase letters, digits, - and _)."

    # --- key
    step "Your SSH key"
    local key def_key="" candidates=() f
    def_key=${ARG_KEY:-$(previous_value "$config" identityfile)}
    local d n c dup
    for d in "$HOME/.ssh" "$sshdir"; do
        for n in id_ed25519 id_ecdsa id_rsa; do
            f="$d/$n"
            [[ -f $f && -f $f.pub ]] || continue
            dup=no
            for c in ${candidates[@]+"${candidates[@]}"}; do [[ $c -ef $f ]] && dup=yes; done
            [[ $dup == no ]] && candidates+=("$f")
        done
    done
    if [[ -z $def_key && ${#candidates[@]} -gt 0 ]]; then def_key=${candidates[0]}; fi
    if [[ -z $ARG_KEY ]]; then
        info "Use the key whose public half is registered in your WATcloud profile."
        if ((${#candidates[@]})); then info "Found: ${candidates[*]}"; fi
    fi
    if [[ -z $def_key && -z $ARG_KEY ]]; then
        warn "no SSH key found in $HOME/.ssh."
        if confirm "Create a new key ($HOME/.ssh/id_ed25519)?"; then
            mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
            ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -C "$CLUSTER_USER@watcloud"
            printf '\n%sNext step: register the new key, then run setup again.%s\n' "$C_YEL" "$C_OFF"
            info "1. Add this public key to your WATcloud profile ($PROFILE_URL):"
            info "   $(cat "$HOME/.ssh/id_ed25519.pub")"
            info "2. Wait for the change to be applied (usually about 15 minutes), then run ./setup.sh again."
            exit 2
        fi
    fi
    ask key "Private key file" "$def_key"
    # shellcheck disable=SC2088 # matching a literal "~/" typed at the prompt
    case $key in "~/"*) key="$HOME/${key#\~/}" ;; esac
    [[ -f $key ]] || fail "key file '$key' does not exist."
    if [[ $key == *.pub ]]; then
        info "Using the public key $key: ssh will ask your SSH agent to sign with it."
    elif [[ ! -f $key.pub ]]; then
        warn "$key.pub is missing; that is fine as long as $key is the private key."
    fi

    FORWARD_AGENT=${ARG_FORWARD:-$(previous_forward_agent "$config")}
    [[ $FORWARD_AGENT == no ]] || FORWARD_AGENT=yes

    SESSION_NAMES=$(previous_sessions "$config")
    # On WSL the Windows config may hold sessions added there (asd-dev.cmd add); keep both lists.
    if [[ $ENV_KIND == wsl && $DO_WINDOWS == yes ]]; then
        local wpc wn
        wpc=$(windows_profile)
        if [[ -n $wpc ]]; then
            for wn in $(previous_sessions "$wpc/.ssh/config"); do
                [[ " $SESSION_NAMES " == *" $wn "* ]] || SESSION_NAMES+=" $wn"
            done
        fi
    fi

    # --- helper directory in the cluster home
    CLUSTER_DIR=${ARG_CLUSTER_DIR:-$(previous_cluster_dir "$config")}
    CLUSTER_DIR=${CLUSTER_DIR:-.asd-dev}
    [[ $CLUSTER_DIR =~ ^[A-Za-z0-9._-]+$ ]] || fail "--cluster-dir must be a plain directory name in your cluster home, like .asd-dev"

    # --- login node
    local login=${ARG_LOGIN:-$(previous_value "$config" hostname)}
    login=${login%%.*}
    login=${login:-wato-login1}
    case $login in wato-login1 | wato-login2) ;; *) fail "--login must be wato-login1 or wato-login2." ;; esac
    LOGIN_HOSTNAME="$login.ext.watonomous.ca"

    # --- test the login with a temporary config that holds only our block
    step "Checking that you can log in to $login as $CLUSTER_USER"
    local out rc
    TMPCFG=$(mktemp "${TMPDIR:-/tmp}/asd-dev-ssh.XXXXXX")
    trap 'rm -f "$TMPCFG"' EXIT
    mkdir -p "$sshdir"
    # Paths in the config must suit the ssh that reads it; on Git Bash that is Windows' ssh too.
    local pathstyle=unix
    [[ $ENV_KIND == gitbash ]] && pathstyle=windows
    local nkey nknown nproxy=""
    nkey=$(native_path "$key" $pathstyle)
    nknown=$(native_path "$known" $pathstyle)
    [[ -n $proxy_f ]] && nproxy=$(native_path "$proxy_f" $pathstyle)
    # shellcheck disable=SC2094 # only the file name is used, not its content
    make_block "$nkey" "$nknown" "$(native_path "$TMPCFG" $pathstyle)" >"$TMPCFG"
    set +o errexit
    out=$(ssh -F "$TMPCFG" -T asd-dev-login 'echo ASD_DEV_LOGIN_OK $(id -un)' 2>&1 </dev/null)
    rc=$?
    set -o errexit
    if [[ $out != *ASD_DEV_LOGIN_OK* ]]; then
        local detail
        detail=$(printf '%s\n' "$out" | grep -v '^Warning: Permanently added' | tail -n 3)
        case $out in
            *"bad permissions"* | *"UNPROTECTED"*)
                if [[ $key == /mnt/[a-z]/* ]]; then
                    fail "ssh ignores the key $key because its permissions are too open." \
                        "Files on the Windows drive cannot be made private from WSL. Copy the key into WSL:" \
                        "  cp '$key' ~/.ssh/ && chmod 600 ~/.ssh/$(basename "$key")" \
                        "then run: ./setup.sh --key ~/.ssh/$(basename "$key")" "ssh said: $detail"
                fi
                fail "ssh ignores the key $key because other users can read it." \
                    "Fix it with: chmod 600 '$key'   then run setup again." "ssh said: $detail"
                ;;
            *"Permission denied"*)
                fail "$login refused the login for '$CLUSTER_USER' with key $key." \
                    "The usual causes:" \
                    "- The username is not your compute cluster username. Use the 'Username' under" \
                    "  'Compute Cluster' in your WATcloud profile, not your WATcloud username: $PROFILE_URL" \
                    "- This key is not in your profile, or the change is not applied yet (about 15 min)." \
                    "- You are not (or no longer) registered for the compute cluster." \
                    "ssh said: $detail"
                ;;
            *"not available"*)
                fail "your account on $login is locked (it may have expired)." "Ask your WATcloud contact to renew it." "ssh said: $detail" ;;
            *"timed out"* | *"No route"* | *"Network is unreachable"*)
                fail "could not reach $LOGIN_HOSTNAME." \
                    "The WATcloud login nodes only accept connections from the UW campus network or the UW VPN." \
                    "Off campus? Connect to the UW VPN ($VPN_URL) and run setup again." \
                    "On campus or on the VPN already? Try the other login node: ./setup.sh --login wato-login2" \
                    "ssh said: $detail"
                ;;
            *"Could not resolve"*)
                fail "could not look up $LOGIN_HOSTNAME; check your internet connection." "ssh said: $detail" ;;
            *"Connection refused"*)
                fail "$login refused the connection; it may be down." \
                    "Try the other login node: ./setup.sh --login wato-login2. Status: https://status.watonomous.ca" \
                    "ssh said: $detail"
                ;;
            *"passphrase"*)
                fail "ssh could not use the key $key." "ssh said: $detail" ;;
            *) fail "logging in to $login failed (exit code $rc)." "ssh said: $detail" ;;
        esac
    fi
    local whoami
    whoami=$(printf '%s\n' "$out" | sed -n 's/.*ASD_DEV_LOGIN_OK //p' | tr -d '\r' | tail -n1)
    ok "  logged in as $whoami"

    # --- install the cluster helper
    step "Installing the session helper in your cluster home (~/$CLUSTER_DIR)"
    local settings_str="" s
    for s in ${CLUSTER_SETTINGS[@]+"${CLUSTER_SETTINGS[@]}"}; do settings_str+=" $s"; done
    set +o errexit
    out=$(ssh -F "$TMPCFG" -T asd-dev-login \
        "mkdir -p $CLUSTER_DIR/tmp && tr -d '\\r' > $CLUSTER_DIR/tmp/asd-dev.new && bash $CLUSTER_DIR/tmp/asd-dev.new --from=unix install$settings_str" \
        <"$HELPER" 2>&1)
    rc=$?
    set -o errexit
    if [[ $out == *ASD_DEV_NEWER_INSTALLED* ]]; then
        fail "your cluster home already has a newer asd-dev than this copy of wato_asd_tooling." \
            "Update this copy (git pull) and run ./setup.sh again."
    fi
    if ((rc != 0)) || [[ $out != *ASD_DEV_INSTALLED* ]]; then
        fail "installing the helper on the cluster failed (exit code $rc):" "$out"
    fi
    HOSTKEY=$(printf '%s\n' "$out" | sed -n 's/^ASD_DEV_HOSTKEY //p' | tr -d '\r')
    [[ -n $HOSTKEY ]] || fail "the cluster did not report the session host key:" "$out"
    printf '%s\n' "$out" | grep '^asd-dev:' || true
    ok "  installed $(printf '%s\n' "$out" | awk '/^ASD_DEV_INSTALLED/ { print "asd-dev " $2 }')"

    # --- write this side's ssh config
    step "Writing the ssh config"
    # A RemoteCommand for all hosts would clash with the commands VS Code and the ProxyCommand run.
    if [[ -f $config ]] && ssh -F "$config" -G asd-dev-session 2>/dev/null </dev/null | grep -qi '^remotecommand '; then
        warn "$config sets RemoteCommand for all hosts; the asd-dev hosts get 'RemoteCommand none' to override it."
        RC_NONE=$'\n    RemoteCommand none'
    fi
    write_known_hosts "$known"
    install_block "$config" "$(make_block "$nkey" "$nknown" "$nproxy")"
    ssh -F "$config" -G asd-dev-session >/dev/null 2>&1 ||
        fail "ssh cannot parse $config after the change." "Your previous file is in $config.asd-dev-backup-*."
    set +o errexit
    out=$(ssh -F "$config" -T asd-dev-login "$CLUSTER_DIR/bin/asd-dev version" 2>&1 </dev/null)
    rc=$?
    set -o errexit
    if ((rc != 0)); then
        if [[ $out == *"ControlPath too long"* ]]; then
            fail "your own ControlPath setting makes a socket path that is too long for this system." \
                "Shorten it in $config (for example ControlPath /tmp/cm-%C) and run setup again." "ssh said: $out"
        fi
        fail "the new config does not work for the login node:" "$out"
    fi
    ok "  checked: 'ssh asd-dev-login' works with the new config"

    # --- WSL: VS Code runs on Windows and uses Windows' ssh, keys and config
    if [[ $ENV_KIND == wsl && $DO_WINDOWS == yes ]]; then
        setup_windows_side "$key"
    fi

    check_vscode "$config"

    step "Done"
    ok "Start a session: $REPO_DIR/asd-dev start   (it waits for the job and then opens VS Code)"
    ok "Then, or any time it runs: VS Code > Remote Explorer > SSH > asd-dev-session > Connect."
    info "It ends at its time limit, or with: ./asd-dev stop (or asd-dev stop in the session's terminal)."
    info "Other commands: ./asd-dev status | config | logs     (terminal: ssh asd-dev-session)"
    if [[ -n $proxy_f ]]; then
        warn "you used --ssh-config: VS Code only uses $config if its 'remote.SSH.configFile' setting points there,"
        warn "and the laptop commands need ASD_DEV_SSH_CONFIG=$config"
    fi
}

setup_windows_side() {
    local key=$1 wp wsshdir wconfig wknown wkey keyname
    step "Configuring Windows (VS Code runs there)"
    wp=$(windows_profile)
    if [[ -z $wp ]]; then
        warn "could not find your Windows user profile from WSL (is Windows interop disabled?)."
        warn "Run setup.cmd from Windows instead so VS Code can connect."
        return
    fi
    wsshdir="$wp/.ssh"
    wconfig="$wsshdir/config"
    wknown="$wsshdir/asd-dev_known_hosts"
    mkdir -p "$wsshdir"
    case $key in
        /mnt/[a-z]/*) wkey=$key ;;
        *)
            # Windows ssh cannot read files inside WSL, so it needs its own copy of the key.
            keyname=$(basename "$key")
            wkey="$wsshdir/asd-dev_$keyname"
            if ! same_file "$key" "$wkey"; then
                info "Windows' ssh cannot use keys stored inside WSL."
                if confirm "Copy $key (and .pub) to $(native_path "$wkey" windows) for VS Code?"; then
                    cp "$key" "$wkey"
                    [[ -f $key.pub ]] && cp "$key.pub" "$wkey.pub"
                    chmod 600 "$wkey" 2>/dev/null || true
                else
                    warn "skipped; VS Code will not be able to connect until Windows has a usable key (run setup.cmd in Windows)."
                    return
                fi
            fi
            ;;
    esac
    write_known_hosts "$wknown"
    RC_NONE=""
    if [[ -f $wconfig ]] && ssh -F "$wconfig" -G asd-dev-session 2>/dev/null </dev/null | grep -qi '^remotecommand '; then
        warn "$(native_path "$wconfig" windows) sets RemoteCommand for all hosts; the asd-dev hosts get 'RemoteCommand none'."
        RC_NONE=$'\n    RemoteCommand none'
    fi
    install_block "$wconfig" "$(make_block "$(native_path "$wkey" windows)" "$(native_path "$wknown" windows)" "")"
    ok "  Windows: $(native_path "$wconfig" windows) now has the asd-dev entries"
}

check_vscode() {
    local config=$1 f dirs=() found=no
    case $ENV_KIND in
        macos) dirs=("$HOME/Library/Application Support/Code/User" "$HOME/Library/Application Support/Cursor/User" "$HOME/Library/Application Support/VSCodium/User") ;;
        linux | chromeos | unknown) dirs=("$HOME/.config/Code/User" "$HOME/.config/Cursor/User" "$HOME/.config/VSCodium/User") ;;
        gitbash) [[ -n ${APPDATA:-} ]] && dirs=("$(cygpath -u "$APPDATA")/Code/User" "$(cygpath -u "$APPDATA")/Cursor/User") ;;
        wsl) local wp; wp=$(windows_profile); [[ -n $wp ]] && dirs=("$wp/AppData/Roaming/Code/User" "$wp/AppData/Roaming/Cursor/User") ;;
    esac
    for f in ${dirs[@]+"${dirs[@]}"}; do
        [[ -d $f ]] && found=yes
        [[ -f $f/settings.json ]] || continue
        if grep -q '"remote.SSH.configFile"' "$f/settings.json"; then
            warn "$f/settings.json sets remote.SSH.configFile; VS Code reads that file, not the default one."
            warn "If connecting fails, run setup again with --ssh-config <that file>."
        fi
        if grep -q '"remote.SSH.path"' "$f/settings.json"; then
            warn "$f/settings.json sets remote.SSH.path (a custom ssh program); setup assumed the default ssh."
        fi
    done
    if [[ $found == no ]]; then
        info "Note: VS Code does not seem to be installed (or never ran) here. Install it and its"
        info "'Remote - SSH' extension (ms-vscode-remote.remote-ssh)."
    fi
}

HOSTKEY="" TMPCFG=""
main
