# One-time setup on native Windows: lets VS Code (and ssh) connect into a WATcloud SLURM session.
# Run it through setup.cmd (double-click, or .\setup.cmd in PowerShell or Command Prompt).
# Same options as setup.sh: .\setup.cmd --user NAME --key PATH --login wato-login1 --yes ...
# Works in Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII-only.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Helper = Join-Path $RepoDir 'cluster\asd-dev'
$BlockBegin = '# >>> asd-dev (wato_asd_tooling) >>>'
$BlockEnd = '# <<< asd-dev (wato_asd_tooling) <<<'
$ProfileUrl = 'https://cloud.watonomous.ca/docs/utilities/profile-editor'
$VpnUrl = 'https://uwaterloo.ca/information-systems-technology/services/virtual-private-network-vpn'

function Info($msg) { Write-Host $msg }
function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host $msg -ForegroundColor Green }
function Warn($msg) { Write-Host "WARNING: $msg" -ForegroundColor Yellow }
function Fail([string]$msg, [string[]]$details = @()) {
    Write-Host ''
    Write-Host "ERROR: $msg" -ForegroundColor Red
    foreach ($d in $details) { Write-Host "  $d" }
    Exit-Setup 1
}

# Keeps the window open when setup.cmd was double-clicked in Explorer.
function Exit-Setup([int]$code) {
    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
        $cmd = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)"
        $grand = Get-CimInstance Win32_Process -Filter "ProcessId=$($cmd.ParentProcessId)"
        if ($grand -and $grand.Name -eq 'explorer.exe') { Read-Host 'Press Enter to close this window' | Out-Null }
    } catch { }
    exit $code
}

function Show-Usage {
    @'
Usage: .\setup.cmd [options]

Sets up this computer so that VS Code's "Remote - SSH" can connect to "asd-dev-session",
a dev session that runs inside a WATcloud SLURM job. Safe to run again at any time.

  --user NAME        your WATcloud compute cluster username (asked if omitted)
  --key PATH         private key registered with WATcloud (asked if omitted); a .pub file
                     works too when the private key only lives in an SSH agent
  --login HOST       wato-login1 (default) or wato-login2
  --ssh-config FILE  ssh config file to write (default: %USERPROFILE%\.ssh\config, which VS Code reads)
  --no-agent-forwarding  do not forward your SSH agent into sessions (it is forwarded by default so
                     git over SSH works there; root on the compute node could use it meanwhile)
  --add-session NAME only add the host asd-dev-session-NAME for a named session to the ssh config
                     (.\asd-dev.cmd add --name NAME and .\asd-dev.cmd start --name NAME call this)
  --cluster-dir DIR  install the cluster helper in ~/DIR instead of ~/.asd-dev (for a second,
                     independent install, e.g. to test another version)
  --yes              do not ask questions; use defaults and the values given
  -h, --help         show this help

Defaults for new sessions (stored on the cluster in ~/.asd-dev/config; only the values given change):
  --cpus N --mem 16G --time 6:00:00 --tmpdisk MiB --vram MiB --gpus N --gpu-type TYPE
  --docker-state yes|no
'@ | Write-Host
}

# ---------------------------------------------------------------- arguments

$ArgUser = ''; $ArgKey = ''; $ArgLogin = ''; $ArgConfig = ''; $ArgClusterDir = ''; $ArgForward = ''; $ArgAdd = ''; $AssumeYes = $false
$ClusterSettings = @()
$settingNames = @('cpus', 'mem', 'time', 'tmpdisk', 'vram', 'gpus', 'gpu-type', 'docker-state')
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    $name = $a.TrimStart('-').ToLowerInvariant()
    $needsValue = $true
    switch ($name) {
        'yes' { $AssumeYes = $true; $needsValue = $false }
        'y' { $AssumeYes = $true; $needsValue = $false }
        'no-agent-forwarding' { $ArgForward = 'no'; $needsValue = $false }
        'agent-forwarding' { $ArgForward = 'yes'; $needsValue = $false }
        'h' { Show-Usage; exit 0 }
        'help' { Show-Usage; exit 0 }
    }
    if (-not $needsValue) { continue }
    if ($i + 1 -ge $args.Count) { Show-Usage; Fail "option $a needs a value" }
    $value = [string]$args[++$i]
    switch ($name) {
        'user' { $ArgUser = $value }
        'key' { $ArgKey = $value }
        'login' { $ArgLogin = $value }
        'ssh-config' { $ArgConfig = $value }
        'cluster-dir' { $ArgClusterDir = $value }
        'add-session' { $ArgAdd = $value.ToLowerInvariant() }
        default {
            if ($settingNames -notcontains $name) { Show-Usage; Fail "unknown option '$a'" }
            if ($value -notmatch '^[A-Za-z0-9_:.-]*$') { Fail "invalid value for ${a}: '$value'" }
            $ClusterSettings += ('{0}={1}' -f $name.Replace('-', '_'), $value)
        }
    }
}

function Ask([string]$question, [string]$default) {
    if ($AssumeYes -or [Console]::IsInputRedirected) { return $default }
    $prompt = if ($default) { "$question [$default]" } else { $question }
    $answer = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer.Trim()
}
function Confirm([string]$question) {
    if ($AssumeYes -or [Console]::IsInputRedirected) { return $true }
    $answer = Read-Host "$question [Y/n]"
    return ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]')
}

# Runs a native program; returns @{ Code; Text } with stdout and stderr merged.
function Invoke-Native([string]$exe, [string[]]$arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $exe @arguments 2>&1 | ForEach-Object { [string]$_ }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return @{ Code = $code; Text = ($lines -join "`n") }
}

# ---------------------------------------------------------------- ssh config

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$script:RcNone = $null

function To-SshPath([string]$p) { return $p.Replace('\', '/') }
function Quote-Value([string]$v) { if ($v -match '\s') { return '"' + $v + '"' } else { return $v } }

function Make-Block([string]$identity, [string]$known, [string]$proxyConfig) {
    $id = Quote-Value (To-SshPath $identity)
    $kh = Quote-Value (To-SshPath $known)
    $proxyF = ''
    if ($proxyConfig) { $proxyF = ' -F ' + (Quote-Value (To-SshPath $proxyConfig)) }
    $lines = @(
        $BlockBegin,
        "# Written by wato_asd_tooling's setup. Run it again to change this block; edits here are lost.",
        '# The login node, used as the hop; the "*" keeps VS Code from listing it (VS Code must not run there).',
        'Host asd-dev-login*',
        "    HostName $script:LoginHostName",
        "    User $script:ClusterUser",
        "    IdentityFile $id",
        '    IdentitiesOnly yes',
        $script:RcNone,
        "    UserKnownHostsFile $kh",
        '    StrictHostKeyChecking accept-new',
        '    ConnectTimeout 10',
        '    ForwardAgent no',
        '    ServerAliveInterval 15',
        '    ServerAliveCountMax 4',
        '',
        '# One entry per session, each passing its own name as a fixed word: no host name that anyone',
        '# types (a git submodule URL, say) reaches a shell, on any client. Add a named session with',
        '# .\asd-dev.cmd add --name NAME (.\asd-dev.cmd start --name NAME does it too).'
    )
    $hosts = 'asd-dev-session'
    foreach ($n in @('default') + @($script:SessionNames)) {
        $alias = if ($n -eq 'default') { 'asd-dev-session' } else { "asd-dev-session-$n" }
        if ($n -ne 'default') { $hosts += " $alias" }
        $lines += "Host $alias"
        $lines += "    ProxyCommand ssh$proxyF -T asd-dev-login $($script:ClusterDir)/bin/asd-dev proxy $alias"
        $lines += $script:RcNone
    }
    $lines += @(
        "Host $hosts",
        "    User $script:ClusterUser",
        "    IdentityFile $id",
        '    IdentitiesOnly yes',
        "    HostKeyAlias $(Get-KhAlias)",
        "    UserKnownHostsFile $kh",
        '    StrictHostKeyChecking yes',
        "    ForwardAgent $($script:ForwardAgent)",
        '    ServerAliveInterval 15',
        '    ServerAliveCountMax 4',
        '',
        '# Ends the block above so that settings below it keep applying to all hosts.',
        'Host *',
        $BlockEnd
    )
    return (($lines | Where-Object { $_ -ne $null }) -join "`n")
}

function Read-Lines([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    # ReadAllText detects a BOM, so a UTF-16 file written by PowerShell's ">" is read correctly too.
    $text = [System.IO.File]::ReadAllText($path)
    if ($text.Length -eq 0) { return @() }
    return ($text -split "`r?`n")
}

function Install-Block([string]$config, [string]$block) {
    $dir = Split-Path -Parent $config
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $old = @(Read-Lines $config)

    # Entries for our host names outside the block. The old setup_slurm_ssh.sh wrote one whose
    # ProxyCommand looks up wato_slurm_dev; only that one is offered for commenting out, and only
    # with the user's consent. A user's own entry is never changed (ours come first and win).
    $hostRe = '^\s*([Hh][Oo][Ss][Tt]|[Mm][Aa][Tt][Cc][Hh])[\s=]'
    $ourRe = '^\s*[Hh][Oo][Ss][Tt][\s=].*asd-dev-session'
    $starts = @{}; $start = -1; $inBlock = $false
    for ($n = 0; $n -lt $old.Count; $n++) {
        $l = $old[$n]
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($l -eq $BlockEnd) { $inBlock = $false; continue }
        if ($inBlock) { continue }
        if ($l -match $hostRe) { $start = -1; if ($l -match $ourRe) { $start = $n; $starts[$n] = $false } ; continue }
        if ($start -ge 0 -and $l -match 'wato_slurm_dev') { $starts[$start] = $true }
    }
    $disable = @{}
    foreach ($n in ($starts.Keys | Sort-Object)) {
        if ($starts[$n]) {
            Warn "$config has an asd-dev-session entry from the previous tooling (line $($n + 1): $($old[$n]))."
            if ($ArgAdd) { Warn 'left as it is; run setup.cmd once to clean it up.' }
            elseif ($AssumeYes) { Info '  commenting it out (--yes)'; $disable[$n] = $true }
            elseif (-not [Console]::IsInputRedirected) { if (Confirm 'Comment it out so it does not interfere?') { $disable[$n] = $true } }
            else { Warn 'left as it is (no console to ask); run setup.cmd in a terminal, or with --yes, to comment it out.' }
        } else {
            Info "  your own entry '$($old[$n].Trim())' (line $($n + 1)) stays; the asd-dev entries come first, so theirs win."
        }
    }

    $rest = New-Object System.Collections.Generic.List[string]
    $inBlock = $false; $skipBlank = $false; $inLegacy = $false
    for ($n = 0; $n -lt $old.Count; $n++) {
        $l = $old[$n]
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($inBlock) { if ($l -eq $BlockEnd) { $inBlock = $false; $skipBlank = $true }; continue }
        if ($skipBlank -and $l -match '^\s*$') { continue }
        $skipBlank = $false
        if ($l -match $hostRe) { $inLegacy = $disable.ContainsKey($n) }
        if ($inLegacy) { $rest.Add("# [disabled by asd-dev setup] $l") } else { $rest.Add($l) }
    }
    while ($rest.Count -gt 0 -and $rest[$rest.Count - 1] -eq '') { $rest.RemoveAt($rest.Count - 1) }
    $new = $block + "`n`n" + (($rest.ToArray()) -join "`n")
    if ($rest.Count -gt 0) { $new += "`n" }

    if (Test-Path -LiteralPath $config) {
        $current = [System.IO.File]::ReadAllText($config)
        if ($current -eq $new) { Info "  $config is already up to date"; return }
        if ($current.Length -gt 0) {
            $backup = "$config.asd-dev-backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $config -Destination $backup
            Info "  backed up the old file to $backup"
            # Keep the three newest backups.
            Get-ChildItem -LiteralPath (Split-Path -Parent $config) -Filter ((Split-Path -Leaf $config) + '.asd-dev-backup-*') |
                Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -ErrorAction SilentlyContinue
        }
    }
    # UTF-8 without BOM: Windows' ssh cannot read UTF-16 or a BOM.
    [System.IO.File]::WriteAllText($config, $new, $Utf8NoBom)
    Ok "  wrote the asd-dev entries at the top of $config"
}

# known_hosts name of the session host key: one per install, so installs sharing an ssh
# directory do not replace each other's key.
function Get-KhAlias { if ($script:ClusterDir -eq '.asd-dev') { 'asd-dev-session' } else { "asd-dev-session@$($script:ClusterDir)" } }

function Write-KnownHosts([string]$file) {
    $alias = Get-KhAlias
    $keep = @(Read-Lines $file | Where-Object { $_ -and -not $_.StartsWith("$alias ") })
    $keep += "$alias $script:HostKey"
    [System.IO.File]::WriteAllText($file, (($keep -join "`n") + "`n"), $Utf8NoBom)
}

function Previous-ClusterDir([string]$config) {
    $inBlock = $false
    foreach ($l in @(Read-Lines $config)) {
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($l -eq $BlockEnd) { break }
        if ($inBlock -and $l -match '^\s*ProxyCommand\s.*\s(\S+)/bin/asd-dev\s') { return $Matches[1] }
    }
    return ''
}

function Previous-Sessions([string]$config) {
    $names = @(); $inBlock = $false
    foreach ($l in @(Read-Lines $config)) {
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($l -eq $BlockEnd) { break }
        if ($inBlock -and $l -match '^\s*Host\s+asd-dev-session-([a-z0-9][a-z0-9_-]*)\s*$') { $names += $Matches[1] }
    }
    return $names
}
function Previous-BlockLine([string]$config, [string]$pattern) {
    $inBlock = $false
    foreach ($l in @(Read-Lines $config)) {
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($l -eq $BlockEnd) { break }
        if ($inBlock -and $l -match $pattern) { return $l }
    }
    return ''
}
function Previous-ForwardAgent([string]$config) {
    $inBlock = $false; $inSession = $false
    foreach ($l in @(Read-Lines $config)) {
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($l -eq $BlockEnd) { break }
        if ($inBlock -and $l -match '^\s*Host\s') { $inSession = ($l -match '^\s*Host\s+asd-dev-session(\s|$)') }
        if ($inBlock -and $inSession -and $l -match '^\s*ForwardAgent\s+(\S+)') { return $Matches[1].ToLowerInvariant() }
    }
    return ''
}

function Previous-Value([string]$config, [string]$keyword) {
    $inBlock = $false; $inLogin = $false
    foreach ($l in @(Read-Lines $config)) {
        if ($l -eq $BlockBegin) { $inBlock = $true; continue }
        if ($l -eq $BlockEnd) { break }
        if (-not $inBlock) { continue }
        $parts = $l.Trim() -split '\s+', 2
        if ($parts.Count -lt 2) { continue }
        if ($parts[0] -eq 'Host') { $inLogin = $parts[1].StartsWith('asd-dev-login'); continue }
        if ($inLogin -and $parts[0] -eq $keyword) { return $parts[1].Trim('"') }
    }
    return ''
}

# ---------------------------------------------------------------- main

if (-not (Test-Path -LiteralPath $Helper)) { Fail "missing $Helper; run setup from a complete copy of wato_asd_tooling." }

# VS Code runs the first ssh.exe on PATH (normally Windows' own OpenSSH), so use the same one.
$sshCmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
if (-not $sshCmd) {
    $builtin = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if (Test-Path $builtin) { $Ssh = $builtin } else {
        Fail 'ssh is not installed.' @(
            'Install the "OpenSSH Client": Settings > System > Optional features > Add a feature,',
            'or in an administrator PowerShell: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0',
            'Then run setup.cmd again.')
    }
} else { $Ssh = $sshCmd.Source }
$Scp = Join-Path (Split-Path -Parent $Ssh) 'scp.exe'
$sshVersion = (Invoke-Native $Ssh @('-V')).Text

$SshDir = Join-Path $env:USERPROFILE '.ssh'
$DefaultConfig = Join-Path $SshDir 'config'
$Config = $DefaultConfig
$ProxyConfig = ''
if ($ArgConfig) {
    $Config = [System.IO.Path]::GetFullPath($ArgConfig)
    $SshDir = Split-Path -Parent $Config
    if ($Config -ne $DefaultConfig) { $ProxyConfig = $Config }
}
$Known = Join-Path $SshDir 'asd-dev_known_hosts'
if (-not (Test-Path -LiteralPath $SshDir)) { New-Item -ItemType Directory -Path $SshDir | Out-Null }

$script:SessionNames = @(Previous-Sessions $Config)

# --add-session: rewrite the block with one more session, from the block's own values.
if ($ArgAdd) {
    if ($ArgAdd -cnotmatch '^[a-z0-9][a-z0-9_-]{0,19}$' -or $ArgAdd -eq 'default') {
        Fail "invalid session name '$ArgAdd'" @("Use up to 20 lowercase letters, digits, '-' or '_'.")
    }
    $script:ClusterUser = Previous-Value $Config 'User'
    if (-not $script:ClusterUser) { Fail "$Config has no asd-dev entries yet; run setup.cmd first." }
    if (Previous-BlockLine $Config "asd-dev proxy ('%h'|%h)") {
        Fail "$Config has asd-dev entries from an earlier version (with %h)." @(
            'Run setup.cmd once (without --add-session); it keeps your settings and sessions.')
    }
    $script:LoginHostName = Previous-Value $Config 'HostName'
    $script:ClusterDir = Previous-ClusterDir $Config
    if (-not $script:ClusterDir) { $script:ClusterDir = '.asd-dev' }
    $script:ForwardAgent = Previous-ForwardAgent $Config
    if (-not $script:ForwardAgent) { $script:ForwardAgent = 'yes' }
    if (Previous-BlockLine $Config '^\s*RemoteCommand\s+none') { $script:RcNone = '    RemoteCommand none' }
    $pc = Previous-BlockLine $Config '^\s*ProxyCommand\s'
    $prevProxy = ''
    if ($pc -match '-F\s+"([^"]+)"') { $prevProxy = $Matches[1] } elseif ($pc -match '-F\s+(\S+)') { $prevProxy = $Matches[1] }
    if ($script:SessionNames -notcontains $ArgAdd) { $script:SessionNames += $ArgAdd }
    Install-Block $Config (Make-Block (Previous-Value $Config 'IdentityFile') (Previous-Value $Config 'UserKnownHostsFile') $prevProxy)
    Ok "VS Code now lists asd-dev-session-$ArgAdd (Remote Explorer > SSH)."
    exit 0
}

Write-Host 'wato_asd_tooling setup: VS Code dev sessions in WATcloud SLURM jobs'
Info "This computer: Windows, $sshVersion ($Ssh). ssh config to write: $Config"

# --- username
Step 'Your cluster username'
$defUser = if ($ArgUser) { $ArgUser } else { Previous-Value $Config 'User' }
if (-not $ArgUser) {
    Info "This is the 'Username' in the 'Compute Cluster' section of your WATcloud profile,"
    Info "the name you use in 'ssh <username>@wato-login1.ext.watonomous.ca'. It can differ from"
    Info "your WATcloud username. Look it up at $ProfileUrl"
}
# Accept "Name" and a pasted "name@wato-login1.ext.watonomous.ca".
$script:ClusterUser = ((Ask 'Cluster username' $defUser) -replace '\s', '' -replace '@.*$', '').ToLowerInvariant()
if (-not $script:ClusterUser) { Fail 'a cluster username is required.' }
if ($script:ClusterUser -cnotmatch '^[a-z_][a-z0-9_-]{0,31}$') {
    Fail "'$($script:ClusterUser)' is not a valid cluster username (lowercase letters, digits, - and _)."
}

# --- key
Step 'Your SSH key'
$candidates = @()
foreach ($n in @('id_ed25519', 'id_ecdsa', 'id_rsa')) {
    $f = Join-Path $SshDir $n
    if ((Test-Path -LiteralPath $f) -and (Test-Path -LiteralPath "$f.pub")) { $candidates += $f }
}
$defKey = if ($ArgKey) { $ArgKey } else { Previous-Value $Config 'IdentityFile' }
if (-not $defKey -and $candidates.Count -gt 0) { $defKey = $candidates[0] }
if (-not $ArgKey) {
    Info 'Use the key whose public half is registered in your WATcloud profile.'
    if ($candidates.Count -gt 0) { Info ('Found: ' + ($candidates -join ', ')) }
}
if (-not $defKey) {
    Warn "no SSH key found in $SshDir."
    if (Confirm "Create a new key ($SshDir\id_ed25519)?") {
        $kg = Join-Path (Split-Path -Parent $Ssh) 'ssh-keygen.exe'
        & $kg -t ed25519 -f (Join-Path $SshDir 'id_ed25519') -C "$($script:ClusterUser)@watcloud"
        $pub = Get-Content -Raw (Join-Path $SshDir 'id_ed25519.pub')
        Write-Host ''
        Write-Host 'Next step: register the new key, then run setup again.' -ForegroundColor Yellow
        Info "1. Add this public key to your WATcloud profile ($ProfileUrl):"
        Info "   $($pub.Trim())"
        Info '2. Wait for the change to be applied (usually about 15 minutes), then run setup.cmd again.'
        Exit-Setup 2
    }
}
$Key = Ask 'Private key file' $defKey
if ($Key.StartsWith('~')) { $Key = Join-Path $env:USERPROFILE $Key.Substring(1).TrimStart('/', '\') }
if (-not (Test-Path -LiteralPath $Key)) { Fail "key file '$Key' does not exist." }
$Key = (Resolve-Path -LiteralPath $Key).Path
if ($Key.EndsWith('.pub')) { Info "Using the public key ${Key}: ssh will ask your SSH agent to sign with it." }

$prevForward = ''
$inBlock = $false
$inSession = $false
foreach ($l in @(Read-Lines $Config)) {
    if ($l -eq $BlockBegin) { $inBlock = $true; continue }
    if ($l -eq $BlockEnd) { break }
    if ($inBlock -and $l -match '^\s*Host\s') { $inSession = ($l -match '^\s*Host\s+asd-dev-session(\s|$)') }
    if ($inBlock -and $inSession -and $l -match '^\s*ForwardAgent\s+(\S+)') { $prevForward = $Matches[1].ToLowerInvariant(); break }
}
$script:ForwardAgent = if ($ArgForward) { $ArgForward } elseif ($prevForward -eq 'no') { 'no' } else { 'yes' }

# --- helper directory in the cluster home
$script:ClusterDir = if ($ArgClusterDir) { $ArgClusterDir } else { Previous-ClusterDir $Config }
if (-not $script:ClusterDir) { $script:ClusterDir = '.asd-dev' }
if ($script:ClusterDir -notmatch '^[A-Za-z0-9._-]+$') { Fail '--cluster-dir must be a plain directory name in your cluster home, like .asd-dev' }

# --- login node
$login = if ($ArgLogin) { $ArgLogin } else { (Previous-Value $Config 'HostName') -replace '\..*$', '' }
if (-not $login) { $login = 'wato-login1' }
if (@('wato-login1', 'wato-login2') -notcontains $login) { Fail '--login must be wato-login1 or wato-login2.' }
$script:LoginHostName = "$login.ext.watonomous.ca"

# --- test the login with a temporary config that holds only our block
Step "Checking that you can log in to $login as $($script:ClusterUser)"
$tmpCfg = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($tmpCfg, (Make-Block $Key $Known $tmpCfg), $Utf8NoBom)
    $r = Invoke-Native $Ssh @('-n', '-F', $tmpCfg, '-T', 'asd-dev-login', 'echo ASD_DEV_LOGIN_OK $(id -un)')
    if ($r.Text -notmatch 'ASD_DEV_LOGIN_OK') {
        $detail = (($r.Text -split "`n") | Where-Object { $_ -notmatch '^Warning: Permanently added' } | Select-Object -Last 3) -join ' / '
        if ($r.Text -match 'UNPROTECTED|bad permissions|too open') {
            # Checked first: ssh then also prints "Permission denied", which would blame the username.
            Fail "Windows' ssh ignores $Key because other users can read it." @(
                'Fix the file permissions in PowerShell, then run setup again:',
                "  icacls `"$Key`" /inheritance:r /grant:r `"$($env:USERNAME):(R)`"",
                "ssh said: $detail")
        } elseif ($r.Text -match 'Permission denied') {
            Fail "$login refused the login for '$($script:ClusterUser)' with key $Key." @(
                'The usual causes:',
                '- The username is not your compute cluster username. Use the ''Username'' under',
                "  'Compute Cluster' in your WATcloud profile, not your WATcloud username: $ProfileUrl",
                '- This key is not in your profile, or the change is not applied yet (about 15 min).',
                '- You are not (or no longer) registered for the compute cluster.',
                "ssh said: $detail")
        } elseif ($r.Text -match 'not available') {
            Fail "your account on $login is locked (it may have expired)." @('Ask your WATcloud contact to renew it.', "ssh said: $detail")
        } elseif ($r.Text -match 'timed out|No route|unreachable') {
            Fail "could not reach $($script:LoginHostName)." @(
                'The WATcloud login nodes only accept connections from the UW campus network or the UW VPN.',
                "Off campus? Connect to the UW VPN ($VpnUrl) and run setup again.",
                'On campus or on the VPN already? Try the other login node: .\setup.cmd --login wato-login2',
                "ssh said: $detail")
        } elseif ($r.Text -match 'Could not resolve') {
            Fail "could not look up $($script:LoginHostName); check your internet connection." @("ssh said: $detail")
        } elseif ($r.Text -match 'refused') {
            Fail "$login refused the connection; it may be down." @(
                'Try the other login node: .\setup.cmd --login wato-login2. Status: https://status.watonomous.ca',
                "ssh said: $detail")
        } else {
            Fail "logging in to $login failed (exit code $($r.Code))." @("ssh said: $detail")
        }
    }
    $whoami = (($r.Text -split "`n") | Where-Object { $_ -match 'ASD_DEV_LOGIN_OK' } | Select-Object -Last 1) -replace '.*ASD_DEV_LOGIN_OK ', ''
    Ok "  logged in as $($whoami.Trim())"

    # --- install the cluster helper (scp copies the bytes as they are; the cluster strips CRs)
    Step "Installing the session helper in your cluster home (~/$($script:ClusterDir))"
    # A relative source path: some scp builds read "C:\..." as host "C".
    Push-Location -LiteralPath $RepoDir
    try { $r = Invoke-Native $Scp @('-q', '-F', $tmpCfg, 'cluster/asd-dev', 'asd-dev-login:.asd-dev-upload') }
    finally { Pop-Location }
    if ($r.Code -ne 0) { Fail "copying the helper to the cluster failed (exit code $($r.Code)):" @($r.Text) }
    $settings = ''
    foreach ($s in $ClusterSettings) { $settings += " $s" }
    $d = $script:ClusterDir
    $remote = "mkdir -p $d/tmp && tr -d '\r' < .asd-dev-upload > $d/tmp/asd-dev.new && rm -f .asd-dev-upload && bash $d/tmp/asd-dev.new --from=windows install$settings"
    $r = Invoke-Native $Ssh @('-n', '-F', $tmpCfg, '-T', 'asd-dev-login', $remote)
    if ($r.Text -match 'ASD_DEV_NEWER_INSTALLED') {
        Fail 'your cluster home already has a newer asd-dev than this copy of wato_asd_tooling.' @(
            'Update this copy (git pull, or download it again) and run setup.cmd again.')
    }
    if ($r.Code -ne 0 -or $r.Text -notmatch 'ASD_DEV_INSTALLED') {
        Fail "installing the helper on the cluster failed (exit code $($r.Code)):" @($r.Text)
    }
} finally {
    Remove-Item -LiteralPath $tmpCfg -ErrorAction SilentlyContinue
}
$out = $r.Text -split "`n"
$script:HostKey = (($out | Where-Object { $_ -match '^ASD_DEV_HOSTKEY ' }) -replace '^ASD_DEV_HOSTKEY ', '').Trim()
if (-not $script:HostKey) { Fail 'the cluster did not report the session host key:' @($r.Text) }
$out | Where-Object { $_ -match '^asd-dev:' } | ForEach-Object { Write-Host $_ }
$installed = ($out | Where-Object { $_ -match '^ASD_DEV_INSTALLED ' }) -replace '^ASD_DEV_INSTALLED (\S+).*', 'asd-dev $1'
Ok "  installed $installed"

# --- write the ssh config
Step 'Writing the ssh config'
# A RemoteCommand for all hosts would clash with the commands VS Code and the ProxyCommand run.
if (Test-Path -LiteralPath $Config) {
    $g = Invoke-Native $Ssh @('-n', '-F', $Config, '-G', 'asd-dev-session')
    if ($g.Text -match '(?m)^remotecommand ') {
        Warn "$Config sets RemoteCommand for all hosts; the asd-dev hosts get 'RemoteCommand none' to override it."
        $script:RcNone = '    RemoteCommand none'
    }
}
Write-KnownHosts $Known
Install-Block $Config (Make-Block $Key $Known $ProxyConfig)
$r = Invoke-Native $Ssh @('-n', '-F', $Config, '-G', 'asd-dev-session')
if ($r.Code -ne 0) { Fail "ssh cannot parse $Config after the change." @($r.Text, "Your previous file is in $Config.asd-dev-backup-*.") }
$r = Invoke-Native $Ssh @('-n', '-F', $Config, '-T', 'asd-dev-login', "$($script:ClusterDir)/bin/asd-dev version")
if ($r.Code -ne 0) { Fail 'the new config does not work for the login node:' @($r.Text) }
Ok "  checked: 'ssh asd-dev-login' works with the new config"

# --- VS Code settings that would make it read another file or use another ssh
foreach ($d in @('Code', 'Cursor', 'VSCodium')) {
    $settingsFile = Join-Path $env:APPDATA "$d\User\settings.json"
    if (-not (Test-Path -LiteralPath $settingsFile)) { continue }
    $json = Get-Content -Raw -LiteralPath $settingsFile
    if ($json -match '"remote\.SSH\.configFile"') {
        Warn "$settingsFile sets remote.SSH.configFile; VS Code reads that file, not $Config."
        Warn 'If connecting fails, run setup again with --ssh-config <that file>.'
    }
    if ($json -match '"remote\.SSH\.path"') {
        Warn "$settingsFile sets remote.SSH.path (a custom ssh program); setup used $Ssh."
    }
}

Step 'Done'
Ok "Start a session: $RepoDir\asd-dev.cmd start   (it waits for the job and then opens VS Code)"
Ok 'Then, or any time it runs: VS Code > Remote Explorer > SSH > asd-dev-session > Connect.'
Info 'It ends at its time limit, or with: .\asd-dev.cmd stop (or asd-dev stop in the session''s terminal).'
Info 'Other commands: .\asd-dev.cmd status | config | logs     (terminal: ssh asd-dev-session)'
if ($ProxyConfig) {
    Warn "you used --ssh-config: VS Code only uses $Config if its 'remote.SSH.configFile' setting points there,"
    Warn "and asd-dev.cmd needs the environment variable ASD_DEV_SSH_CONFIG=$Config"
}
Exit-Setup 0
