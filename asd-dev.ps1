# asd-dev (Windows side): start, stop and check your WATcloud dev sessions from this computer.
# Run it through asd-dev.cmd: .\asd-dev.cmd start | stop | status | logs | config | code | ssh | setup
# Each command runs ~/.asd-dev/bin/asd-dev on the login node; "start" then opens VS Code.
# Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SshArgs = @()
if ($env:ASD_DEV_SSH_CONFIG) { $SshArgs += @('-F', $env:ASD_DEV_SSH_CONFIG) }

function Show-Usage {
    @'
Usage: .\asd-dev.cmd COMMAND [args]

  start [--name NAME] [options]  start a session, wait until it is ready, open VS Code
                          options are sbatch's: --cpus-per-task/-c N --mem 16G --time/-t 6:00:00
                          --gres tmpdisk:MiB,shard:MiB --gpus/-G N --partition/-p NAME
                          --nodelist/-w NODES --exclude/-x NODES; also --docker-state yes|no,
                          --no-code (do not open VS Code), --folder PATH
  code [--name NAME] [--folder PATH]  open VS Code in a running session
  add --name NAME         add the host asd-dev-session-NAME for a named session (start does it too)
  stop [--name NAME] [--now]  stop a session (--all: every session)
  status [--name NAME]    list your sessions
  logs [--name NAME] [-f] show a session's log
  config [options]        show or change your session defaults (the options of start;
                          --unset OPTION removes one), e.g. config --gres tmpdisk:40960
  ssh [--name NAME] [command]  open a terminal (or run a command) in a session
  setup [options]         run setup

Without --name a command means the default session; --name gpu means asd-dev-session-gpu.
Connecting VS Code only connects: start a session first with "start"; it ends at its time
limit or with "stop".
'@ | Write-Host
}

# The helper path from the session host's ProxyCommand (setup's --cluster-dir can change it).
function Get-HelperPath {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'  # 5.1 turns redirected native stderr into errors
    try { $pc = & ssh.exe -n @SshArgs -T -G asd-dev-session 2>$null | Where-Object { $_ -match '^proxycommand ' } | Select-Object -First 1 }
    finally { $ErrorActionPreference = $old }
    if ($pc -and ($pc -match '\s(\S+/bin/asd-dev)(\s|$)')) { return $Matches[1] }
    return '.asd-dev/bin/asd-dev'
}

function Invoke-Remote([string[]]$words) {
    foreach ($w in $words) {
        if ($w -notmatch '^[A-Za-z0-9_:.,=/+-]*$') { Write-Host "asd-dev: unsupported character in '$w'"; exit 1 }
    }
    # --from tells the helper to print command hints in this wrapper's form (.\asd-dev.cmd ...).
    $cmd = (Get-HelperPath) + ' --from=windows ' + ($words -join ' ')
    & ssh.exe -n @SshArgs -T asd-dev-login $cmd
    if ($LASTEXITCODE -eq 255) {
        [Console]::Error.WriteLine('asd-dev: ssh to the login node failed (see above). Timed out? Off campus you need the UW VPN.')
        [Console]::Error.WriteLine('         Permission denied or an unknown host? Run .\setup.cmd again.')
    }
}

# A named session needs its own host entry before ssh or VS Code can reach it.
function Ensure-Host([string]$name) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $dflt = & ssh.exe -n @SshArgs -T -G asd-dev-session 2>$null | Where-Object { $_ -match '^proxycommand ' } }
    finally { $ErrorActionPreference = $old }
    # Entries from before the per-session layout pass %h, which a crafted host name could abuse.
    if ($dflt -and ($dflt -match "asd-dev proxy ('%h'|%h)")) {
        Write-Host 'asd-dev: your ssh config has asd-dev entries from an earlier version; run setup.cmd again (it keeps your settings).'
        exit 1
    }
    if (-not $name -or $name -eq 'default') { return }
    $ErrorActionPreference = 'Continue'
    try { $pc = & ssh.exe -n @SshArgs -T -G "asd-dev-session-$name" 2>$null | Where-Object { $_ -match '^proxycommand ' } }
    finally { $ErrorActionPreference = $old }
    if (-not $pc) {
        $setupArgs = @('--add-session', $name)
        if ($env:ASD_DEV_SSH_CONFIG) { $setupArgs += @('--ssh-config', $env:ASD_DEV_SSH_CONFIG) }
        & (Join-Path $RepoDir 'setup.ps1') @setupArgs
    }
}

function Stop-Unexpected([string]$word) {
    [Console]::Error.WriteLine("asd-dev: ERROR: unexpected argument '$word'; to name a session use --name $word")
    exit 1
}

function Get-Value([string[]]$list, [int]$i) { # the value after option $list[$i]
    if ($i + 1 -ge $list.Count) { [Console]::Error.WriteLine("asd-dev: ERROR: $($list[$i]) needs a value"); exit 1 }
    return $list[$i + 1]
}

function Get-Alias([string]$name) { if (-not $name -or $name -eq 'default') { 'asd-dev-session' } else { "asd-dev-session-$name" } }

function Open-Code([string]$alias, [string]$folder) {
    if (-not $folder) {
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'  # ssh -G warns about the pty when stdin is not a console
        try { $user = (& ssh.exe -n @SshArgs -T -G $alias 2>$null | Where-Object { $_ -match '^user ' } | Select-Object -First 1) -replace '^user ', '' }
        finally { $ErrorActionPreference = $old }
        $folder = "/home/$user"
    }
    $uri = "vscode-remote://ssh-remote+$alias$folder"
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Write-Host "Opening VS Code: $uri"
        & code --folder-uri $uri
    } else {
        Write-Host "VS Code's 'code' command is not on your PATH. In VS Code: Remote Explorer > SSH > $alias > Connect"
    }
}

$cmd = if ($args.Count -gt 0) { [string]$args[0] } else { 'help' }
$rest = @()
if ($args.Count -gt 1) { $rest = @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) }

switch ($cmd) {
    'start' {
        $words = @('start'); $noCode = $false; $folder = ''; $name = ''
        for ($i = 0; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '--no-code') { $noCode = $true }
            elseif ($rest[$i] -eq '--folder') { $folder = Get-Value $rest $i; $i++ }
            elseif ($rest[$i].StartsWith('--folder=')) { $folder = $rest[$i].Substring(9) }
            elseif ($rest[$i] -eq '--name') { $name = Get-Value $rest $i; $words += $rest[$i]; $words += $name; $i++ }
            elseif ($rest[$i].StartsWith('--name=')) { $name = $rest[$i].Substring(7); $words += $rest[$i] }
            # Session options go to the cluster helper, which checks them.
            else { $words += $rest[$i] }
        }
        Ensure-Host $name.ToLowerInvariant()
        # stdout carries only the "ASD_DEV_READY <alias> <job>" line; messages go to stderr (the console).
        $out = @(Invoke-Remote $words)
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $ready = $out | Where-Object { $_ -match '^ASD_DEV_READY ' } | Select-Object -Last 1
        if (-not $ready) { exit 1 }
        if (-not $noCode) { Open-Code (($ready -split ' ')[1]) $folder }
    }
    { $_ -in @('code', 'open') } {
        $name = ''; $folder = ''
        for ($i = 0; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '--folder') { $folder = Get-Value $rest $i; $i++ }
            elseif ($rest[$i] -eq '--name') { $name = Get-Value $rest $i; $i++ }
            elseif ($rest[$i].StartsWith('-')) { Write-Host "unknown option $($rest[$i])"; exit 1 }
            else { Stop-Unexpected $rest[$i] }
        }
        Ensure-Host $name
        Open-Code (Get-Alias $name) $folder
    }
    { $_ -in @('ssh', 'shell') } {
        $name = ''
        if ($rest.Count -ge 1 -and $rest[0] -eq '--name') { $name = Get-Value $rest 0; $rest = @($rest | Select-Object -Skip 2) }
        Ensure-Host $name
        & ssh.exe @SshArgs (Get-Alias $name) @rest
        exit $LASTEXITCODE
    }
    { $_ -in @('stop', 'status', 'logs', 'log', 'config', 'version') } {
        Invoke-Remote (@($cmd) + $rest)
        exit $LASTEXITCODE
    }
    'add' {
        if ($rest.Count -ge 1 -and $rest[0] -eq '--name') { Ensure-Host (Get-Value $rest 0).ToLowerInvariant() }
        elseif ($rest.Count -ge 1 -and -not $rest[0].StartsWith('-')) { Stop-Unexpected $rest[0] }
        else { Show-Usage; exit 1 }
    }
    'setup' {
        & (Join-Path $RepoDir 'setup.ps1') @rest
        exit $LASTEXITCODE
    }
    { $_ -in @('help', '-h', '--help') } { Show-Usage }
    default { Show-Usage; exit 1 }
}
