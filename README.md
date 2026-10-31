# WATO ASD Tooling: VS Code inside a WATcloud SLURM job

This repo connects VS Code on your computer to a dev session that runs as a SLURM job on the
WATcloud compute cluster. You get the job's CPUs, RAM and (optionally) GPU, your cluster home
directory, and a working `docker` in VS Code's terminal.

You set it up once. After that you start a session with `./asd-dev start`, which waits for the
job and opens VS Code in it, and you end it with `./asd-dev stop` (or let its time limit end it).

## Before you start

- You have WATcloud compute cluster access and know your **cluster username**. It is the
  "Username" in the "Compute Cluster" section of your
  [WATcloud profile](https://cloud.watonomous.ca/docs/utilities/profile-editor), the name you
  use in `ssh <username>@wato-login1.ext.watonomous.ca`. It can differ from your WATcloud username.
- The SSH key registered in that profile is on this computer (usually `~/.ssh/id_ed25519`).
- You are on the UW campus network or connected to the
  [UW VPN](https://uwaterloo.ca/information-systems-technology/services/virtual-private-network-vpn).
  The WATcloud login nodes accept no other connections.
- [VS Code](https://code.visualstudio.com/) with the
  [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
  extension is installed.
- You have this repo: `git clone https://github.com/WATonomous/wato_asd_tooling.git`
  (or download it as a ZIP from GitHub and unpack it).

## 1. Set up (once per computer)

Open a terminal in the `wato_asd_tooling` folder and run the line for your system:

| Your system | Run |
| --- | --- |
| macOS, Linux, ChromeOS (Linux) | `./setup.sh` |
| Windows (PowerShell or Command Prompt) | `.\setup.cmd` (or double-click `setup.cmd` in Explorer) |
| Windows with WSL | `./setup.sh` inside WSL (it also sets up Windows, where VS Code runs), or `.\setup.cmd` in Windows |
| Windows with Git Bash | `./setup.sh` |

Setup asks for your cluster username and key, checks that you can log in, installs a small
helper in your cluster home (`~/.asd-dev`), and adds the hosts `asd-dev-session` (your
session) and `asd-dev-login` (the login node it connects through) to the top of your SSH config
(`~/.ssh/config`; a backup of the old file is kept next to it). Run it again at any time to
change the username or key.

Your SSH agent is forwarded into sessions so that `git` over SSH works there. While you are
connected, anything in the session (and the node's administrators) can use the keys in your
agent; run setup with `--no-agent-forwarding` if you do not want that.

## 2. Start a session and connect

```bash
./asd-dev start          # on Windows: .\asd-dev.cmd start
```

On your computer, run `./asd-dev` from the `wato_asd_tooling` folder (on Windows `.\asd-dev.cmd`);
it is not on your PATH. Inside a session's terminal the same commands are just `asd-dev`.

`start` submits the session job with your defaults (4 CPUs, 16 GB RAM, 10 GiB of `/tmp`, no GPU,
6 hours), shows what it is waiting for if the cluster is busy, and opens VS Code in it once it
runs (`--no-code` skips that). While it runs you can also connect yourself: in VS Code open the
**Remote Explorer**, pick **SSH**, hover over **asd-dev-session** and click the arrow, or press
F1 and run **Remote-SSH: Connect to Host...**. Connecting never starts a session; without one,
VS Code reports that it could not connect (see Troubleshooting).

On Windows, the first connection asks for the platform of the remote host: choose **Linux**.
The question can be hidden behind VS Code's welcome or sign-in dialog; if nothing seems to
happen, close that dialog. The first connection with a new VS Code version also installs VS
Code's server in your cluster home (`~/.vscode-server`, about 1.3 GB), which takes under a minute.

Then open a folder (for example `~/wato_monorepo`) and a terminal. `docker` works there; the
docker daemon may need a few more seconds after the session starts.

## 3. Stop

Run `./asd-dev stop` on your computer or `asd-dev stop` in the session's terminal. Otherwise
the session ends at its time limit: 5 minutes before it, to save docker state (a 10-minute
warning appears in your terminals). Closing VS Code does not end it.

Ending a session saves your docker images and containers; the next session restores them.
Saved docker state lives in `/mnt/wato-drive/slurm-docker-sessions/<your uid>/`. If a saved
state cannot be restored (for example because the new session has less `/tmp` than it needs),
docker starts empty, saving is turned off for that session so the saved state is kept, and your
terminal says how to start again.

## Choosing resources (GPUs and more)

Start a session with other resources once:

```bash
./asd-dev start --vram 8192                  # an 8 GiB slice of a GPU (shared with others)
./asd-dev start --gpus 1 --gpu-type rtx_3090  # a whole GPU of a given type
./asd-dev start --cpus 8 --mem 32G --time 4:00:00 --tmpdisk 40960
```

Or change your defaults, which every new session uses:

```bash
./asd-dev config vram=8192 mem=32G       # on your computer
asd-dev config vram=8192 mem=32G         # or in a session's terminal
./asd-dev config                         # show the current defaults
```

`tmpdisk` is the job's `/tmp` in MiB, where docker keeps its images and containers. The default
is 10240 (10 GiB), which holds VS Code's server download and a few small images; the monorepo's
bigger images may need more, and docker fails with "no space left on device" when it runs out. To
see how much your session uses, run `watcloud quota disk` in the session's terminal (the
`TEMP — /tmp` part); the session also warns in your terminals when `/tmp` is 90% full. **For
CARLA, run `./asd-dev config tmpdisk=40960` once** (its image unpacks to about 25 GiB); the
setting stays. Two nodes have only about 66 GiB to give, so above about 66000 only the larger
nodes can run the session.

GPU types: `rtx_2080_ti`, `rtx_3090`, `rtx_4090`, `gtx_1080`. A GPU slice (`--vram`) is how much
of a card SLURM reserves for you, not a limit: `nvidia-smi` shows the whole card and nothing
stops a program from using more, so stay within what you asked for.

A running session keeps its resources; to change them, stop it and start again. The meaning of
every setting is in `~/.asd-dev/config` on the cluster.

## Docker and the monorepo's images

Docker runs inside the session, and VS Code uses it too: `DOCKER_HOST` is set for VS Code's
server, so the terminal, the Docker extension and Dev Containers' **Attach to Running
Container** reach the session's docker (attaching was checked from the command line, not in
VS Code's window). Images, containers and each attached container's VS Code server (a few
hundred MB) all take space in the session's `/tmp`.

The monorepo's module images on GHCR (`ghcr.io/watonomous/wato_monorepo/...`) are private. To
pull them, log in once in a session's terminal with a GitHub classic personal access token that
has the `read:packages` scope (your GitHub account needs access to WATonomous's packages):

```bash
docker login ghcr.io -u <your GitHub username> --password-stdin   # paste the token, Enter, Ctrl-D
```

The login is saved in `~/.docker/config.json` in your cluster home, so later sessions have it.
The monorepo's DEVELOPING.md asks for `write:packages`, which is only needed to push images.
Without a login `watod build` still works: it builds from the public base image, only slower.

## More than one session

Give a session a name with `--name`: `./asd-dev start --name carla --tmpdisk 40960 --vram 8192`.
The first time, this also adds the host `asd-dev-session-carla` to your SSH config, and VS Code
lists it from then on. Names are lowercase (ssh matches host names exactly). Every command that
acts on one session takes the same `--name`, for example `./asd-dev stop --name carla`; without
it a command means the default session (in a session's terminal: that session).
`./asd-dev add --name carla` adds the host without starting anything (needed when you start a
named session on the cluster side). Each name has its own saved docker state.

## Commands

On your computer (`.\asd-dev.cmd` on Windows) or, without the `./`, in a session's terminal
(`code`, `add` and `ssh` only on your computer):

| Command | What it does |
| --- | --- |
| `./asd-dev start [--name NAME] [options]` | start a session, wait until it is ready, open VS Code |
| `./asd-dev stop [--name NAME]` | stop a session (`--now` skips saving docker state, `--all` stops all) |
| `./asd-dev status [--name NAME]` | list your sessions with node, time left and resources |
| `./asd-dev logs [--name NAME]` | show a session's log (`-f` to follow) |
| `./asd-dev config [key=value ...]` | show or change your defaults |
| `./asd-dev code [--name NAME]` | open VS Code in a running session (`--folder PATH` picks the folder) |
| `./asd-dev add --name NAME` | add the host `asd-dev-session-NAME` for a named session to your SSH config |
| `./asd-dev ssh [--name NAME] [command]` | open a terminal in a session, or run a command there (same as `ssh asd-dev-session`) |

`ssh asd-dev-session` also works in any terminal on your computer, and so do `scp` and `rsync`.

## Troubleshooting

When VS Code cannot connect, its dialog often says only "An unknown error occurred". The reason
is in its log: View > Output, choose **Remote - SSH**, and look for lines starting with `asd-dev:`.

| You see | What to do |
| --- | --- |
| `asd-dev: ERROR: no session 'default' is running` | Start one: `./asd-dev start`. |
| `asd-dev: ERROR: session ... is still waiting to start` | The cluster is busy; `./asd-dev start` showed (and `./asd-dev status` shows) why. Connect once it runs. |
| `asd-dev: ... held back by your per-user limit` | Your other jobs use your share (`squeue --me` on the login node). Stop some, or ask for less. |
| `Connection timed out` (for `wato-login1.ext.watonomous.ca`) | You are off campus without the UW VPN. Connect to the VPN and retry. |
| `Permission denied (publickey)` | Wrong username or a key that is not registered. Run setup again; it checks both. |
| `.asd-dev/bin/asd-dev: No such file or directory` | The helper is missing from your cluster home. Run setup again. |
| `Host key verification failed` | The session host key changed (for example `~/.asd-dev` was deleted). Run setup again. |
| `Could not resolve hostname asd-dev-session...` | Your SSH config has no entry for that host. Run setup again, or `./asd-dev add --name NAME`. |
| `Disk quota exceeded` in your home | VS Code keeps its server (about 1.3 GB per VS Code version) in `~/.vscode-server`, in your 20 GiB home. Delete old versions there. |
| `Cannot connect to the Docker daemon` | Docker is still starting (restoring saved state can take minutes). See `./asd-dev logs`. |

If a saved docker state cannot be restored because it is damaged, the session says so, starts
docker empty and leaves the file alone. `./asd-dev start --reset-docker-state` (stop the running
session first) moves it aside as `<file>.old-<date>` and starts fresh; after two failed restores
in a row this happens by itself. The two newest moved-aside copies are kept, older ones are
deleted. `--no-docker-state` starts one session without restoring or saving anything and leaves
the file untouched. The files are in `/mnt/wato-drive/slurm-docker-sessions/<uid>/`:
`slurm-docker-state.tar.zst` for the default session, `slurm-docker-state-<name>.tar.zst` for
named ones (installs made with `setup --cluster-dir` add their directory name).

To undo setup, delete the lines between `# >>> asd-dev` and `# <<< asd-dev` in your SSH config and
the `~/.asd-dev` folder in your cluster home.

## How it works

`./asd-dev start` runs `~/.asd-dev/bin/asd-dev start` on the login node, which submits the
session job with `sbatch` and waits until the job's own `sshd` is listening. That sshd runs as
you on a free port, accepts the keys registered in your WATcloud profile, and uses a host key kept
in `~/.asd-dev`. The SSH host `asd-dev-session` has a `ProxyCommand` that logs in to `wato-login1`
and runs `asd-dev proxy`, which looks up your running session with `squeue --me` and connects
VS Code's SSH stream to its sshd. VS Code's server and terminals therefore run inside the job and
use its resources.

## Coming from the old scripts

`start_interactive_session.sh`, `session_config.sh` and the `ssh_helpers/` scripts are gone;
`./setup.sh` and `./asd-dev` replace them, and your resource settings now live in
`./asd-dev config`. Stop any session the old scripts started with `scancel <job id>`
(`squeue --me` on the login node lists it as `wato_slurm_dev`); the new tooling does not touch
those jobs. If `git pull` refuses because you edited `session_config.sh`, run
`git checkout -- session_config.sh` (or `git stash`) first. Setup offers to comment out the old
`asd-dev-session` entry in your SSH config, which would otherwise get in the way. Saved docker
state carries over: the default session uses the same file as the old scripts.
