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

  start [NAME] [options]  start a session (if needed), wait until it is ready, open VS Code
                          options: --cpus N --mem 16G --time 6:00:00 --vram MiB --gpus N
                          --gpu-type TYPE --tmpdisk MiB --idle-timeout MIN; --no-code; --folder PATH
  code [NAME] [--folder PATH]  open VS Code in a session (connecting starts one if needed)
  stop [NAME] [--now]     stop a session (--all: every session)
  status                  list your sessions
  logs [NAME] [-f]        show a session's log
  config [key=value ...]  show or change your session defaults (stored on the cluster)
  ssh [--name NAME] [command]  open a terminal (or run a command) in a session
  setup [options]         run setup

Usually you only need VS Code: connect to "asd-dev-session" and a session starts by itself.
'@ | Write-Host
}

# The helper path from the session host's ProxyCommand (setup's --cluster-dir can change it).
function Get-HelperPath {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'  # 5.1 turns redirected native stderr into errors
    try { $pc = & ssh.exe @SshArgs -G asd-dev-session 2>$null | Where-Object { $_ -match '^proxycommand ' } | Select-Object -First 1 }
    finally { $ErrorActionPreference = $old }
    if ($pc -and ($pc -match '\s(\S+/bin/asd-dev)(\s|$)')) { return $Matches[1] }
    return '.asd-dev/bin/asd-dev'
}

function Invoke-Remote([string[]]$words) {
    foreach ($w in $words) {
        if ($w -notmatch '^[A-Za-z0-9_:.=/+-]*$') { Write-Host "asd-dev: unsupported character in '$w'"; exit 1 }
    }
    $cmd = (Get-HelperPath) + ' ' + ($words -join ' ')
    & ssh.exe @SshArgs -T asd-dev-login $cmd
    if ($LASTEXITCODE -eq 255) {
        [Console]::Error.WriteLine('asd-dev: ssh to the login node failed (see above). Timed out? Off campus you need the UW VPN.')
        [Console]::Error.WriteLine('         Permission denied or an unknown host? Run .\setup.cmd again.')
    }
}

function Get-Alias([string]$name) { if (-not $name -or $name -eq 'default') { 'asd-dev-session' } else { "asd-dev-session-$name" } }

function Open-Code([string]$alias, [string]$folder) {
    if (-not $folder) {
        $user = (& ssh.exe @SshArgs -G $alias | Where-Object { $_ -match '^user ' } | Select-Object -First 1) -replace '^user ', ''
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
        $words = @('start'); $noCode = $false; $folder = ''
        for ($i = 0; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '--no-code') { $noCode = $true }
            elseif ($rest[$i] -eq '--folder') { $folder = $rest[++$i] }
            else { $words += $rest[$i] }
        }
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
            if ($rest[$i] -eq '--folder') { $folder = $rest[++$i] } else { $name = $rest[$i] }
        }
        Open-Code (Get-Alias $name) $folder
    }
    { $_ -in @('ssh', 'shell') } {
        $name = ''
        if ($rest.Count -gt 1 -and ($rest[0] -eq '--name' -or $rest[0] -eq '-n')) { $name = $rest[1]; $rest = @($rest | Select-Object -Skip 2) }
        & ssh.exe @SshArgs (Get-Alias $name) @rest
        exit $LASTEXITCODE
    }
    { $_ -in @('stop', 'status', 'logs', 'log', 'config', 'version') } {
        Invoke-Remote (@($cmd) + $rest)
        exit $LASTEXITCODE
    }
    'setup' {
        & (Join-Path $RepoDir 'setup.ps1') @rest
        exit $LASTEXITCODE
    }
    { $_ -in @('help', '-h', '--help') } { Show-Usage }
    default { Show-Usage; exit 1 }
}
