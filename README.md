# WATO ASD Tooling: VS Code inside a WATcloud SLURM job

This repo connects VS Code on your computer to a dev session that runs as a SLURM job on the
WATcloud compute cluster. You get the job's CPUs, RAM and (optionally) GPU, your cluster home
directory, and a working `docker` in VS Code's terminal.

You set it up once. After that, connecting VS Code to `asd-dev-session` is the whole workflow:
if no session is running, connecting starts one.

## Before you start

- You have WATcloud compute cluster access and know your **cluster username**. It is the
  "Username" in the "Compute Cluster" section of your
  [WATcloud profile](https://cloud.watonomous.ca/docs/utilities/profile-editor), the name you
  use in `ssh <username>@wato-login1.ext.watonomous.ca`. It can differ from your WATcloud username.
- The SSH key registered in that profile is on this computer (usually `~/.ssh/id_ed25519`).
- You are on the UW campus network or connected to the
  [UW VPN](https://uwaterloo.ca/information-systems-technology/services/virtual-private-network-vpn).
  The WATcloud login nodes accept no other connections, so setup and every connection need it.
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

## 2. Connect

In VS Code, open the **Remote Explorer** in the left bar, pick **SSH**, hover over
**asd-dev-session** and click the arrow ("Connect in Current Window"). Or press F1, run
**Remote-SSH: Connect to Host...** and choose `asd-dev-session`.

On Windows, the first connection asks for the platform of the remote host: choose **Linux**.
The question can be hidden behind VS Code's welcome or sign-in dialog; if nothing seems to
happen, close that dialog. (macOS and Linux detect the platform themselves.)

If you have no session running, connecting starts one with your defaults (4 CPUs, 16 GB RAM,
32 GiB of `/tmp`, no GPU, 6 hours). When the cluster has room this takes a few seconds; the
first connection with a new VS Code version also installs VS Code's server in your cluster home
(`~/.vscode-server`, about 1.3 GB), which takes under a minute.

Then open a folder (for example `~/wato_monorepo`) and a terminal. `docker` works there; the
docker daemon may need a few more seconds after the session starts.

> **If VS Code says "An unknown error occurred"** (or any other connection error), the reason is
> in its log: View > Output, choose **Remote - SSH** in the list on the right, and look for lines
> starting with `asd-dev:`. The two common cases follow.

Connecting does not start a new session within 3 hours after your last one ended by its time
limit, by `asd-dev stop`, or by a failure. VS Code reconnects on its own for hours after a
connection drops, and reopens remote windows when it starts, so without this rule a window left
open would book one job after another. VS Code then reports that it could not connect, and its
log says why the last session ended. Start a new one yourself with `./asd-dev start` (it opens
VS Code when the session is ready). A session that stopped because nothing was connected does
not count: connecting again starts a new one right away.

If the cluster is busy, VS Code reports that it could not connect. Its log (Output panel,
"Remote - SSH") then has a line starting with `asd-dev:` that says why, for example
`job 123 is waiting for free resources`. The job stays queued; click **Retry** later, or run
`./asd-dev start` in a terminal on your computer, which waits and opens VS Code when the
session is ready.

## 3. Stop

A session stops by itself 60 minutes after the last connection to it closes (closing VS Code,
or your laptop going to sleep), or 5 minutes before its time limit (to save docker state; without
docker state it runs to the limit). A running `tmux` or `screen`
keeps it alive while you are disconnected. A VS Code window that stays open keeps the session
running until its time limit, so close the window when you are done.

To stop it now, run `asd-dev stop` in the VS Code terminal, or `./asd-dev stop` on your computer.
After you stop a session, connecting from VS Code does not start a new one for 3 hours (see
step 2); run `./asd-dev start` when you want the next one sooner.
Stopping saves your docker images and containers; the next session restores them. Saved docker
state lives in `/mnt/wato-drive/slurm-docker-sessions/<your uid>/`. If a saved state cannot be
restored (for example because the new session has less `/tmp` than it needs), docker starts
empty, saving is turned off for that session so the saved state is kept, and your terminal says
how to start again with enough `/tmp`.

## Choosing resources (GPUs and more)

Start a session with other resources once:

```bash
./asd-dev start --vram 8192                  # an 8 GiB slice of a GPU (shared with others)
./asd-dev start --gpus 1 --gpu-type rtx_3090  # a whole GPU of a given type
./asd-dev start --cpus 8 --mem 32G --time 4:00:00 --tmpdisk 40960
```

Or change your defaults, which every new session uses (also when VS Code starts one):

```bash
./asd-dev config vram=8192 mem=32G       # on your computer
asd-dev config vram=8192 mem=32G         # or in the VS Code terminal
./asd-dev config                         # show the current defaults
```

GPU types: `rtx_2080_ti`, `rtx_3090`, `rtx_4090`, `gtx_1080`. A GPU slice (`--vram`) is how
much of a card SLURM reserves for you, not a limit: `nvidia-smi` shows the whole card and nothing
stops a program from using more, so stay within what you asked for. `tmpdisk` is the job's `/tmp` in MiB
(default 32768, i.e. 32 GiB), where docker keeps its images and containers. Two nodes have only about
66 GiB to give, so asking for more than that (`--tmpdisk 67000` or above) can make you wait for the
larger nodes. The session warns in your terminals when `/tmp` is 90% full. A running session keeps
its resources; to change them, stop it and start again. The meaning of every setting is in
`~/.asd-dev/config` on the cluster.

## More than one session

Give a session a name: `./asd-dev start gpu --vram 8192`. The first time, this also adds the
host `asd-dev-session-gpu` to your SSH config, and VS Code lists it from then on; connect to it
like `asd-dev-session`. Host names are lowercase (ssh matches them exactly). `./asd-dev add gpu` adds the host without starting anything (needed when
you start a named session from the cluster side, for example in a VS Code terminal). Stop it with
`./asd-dev stop gpu`. Each name has its own saved docker state.

## Commands

On your computer (`.\asd-dev.cmd` on Windows) or, without the `./`, in a session's terminal:

| Command | What it does |
| --- | --- |
| `./asd-dev start [NAME] [options]` | start a session if needed, wait until it is ready, open VS Code |
| `./asd-dev stop [NAME]` | stop a session (`--now` skips saving docker state, `--all` stops all) |
| `./asd-dev status` | list your sessions with node, time left and resources |
| `./asd-dev logs [NAME]` | show a session's log (`-f` to follow) |
| `./asd-dev config [key=value ...]` | show or change your defaults |
| `./asd-dev add NAME` | add the host `asd-dev-session-NAME` for a named session to your SSH config |
| `./asd-dev ssh [--name NAME] [command]` | open a terminal in a session, or run a command there (same as `ssh asd-dev-session`) |

`ssh asd-dev-session` also works in any terminal on your computer, and so do `scp` and `rsync`.

## Troubleshooting

When VS Code cannot connect, its dialog often says only "An unknown error occurred". The lines
that explain it are in its log. Most problems are one of these:

| You see | What to do |
| --- | --- |
| VS Code: "An unknown error occurred. Please consult the log" | View > Output, choose **Remote - SSH**, and read the lines starting with `asd-dev:` (and the rows below). |
| `Connection timed out` (for `wato-login1.ext.watonomous.ca`) | You are off campus without the UW VPN. Connect to the VPN and retry. |
| `Permission denied (publickey)` | Wrong username or a key that is not registered. Run setup again; it checks both. |
| `asd-dev: job N is waiting ...` | The cluster is busy. Click Retry later, or run `./asd-dev start` to wait for it. |
| `asd-dev: ... held back by your per-user limit` | Your other jobs use your share (`squeue --me` on the login node). Stop some, or ask for less. |
| `.asd-dev/bin/asd-dev: No such file or directory` | The helper is missing from your cluster home. Run setup again. |
| `Host key verification failed` | The session host key changed (for example `~/.asd-dev` was deleted). Run setup again. |
| `Could not resolve hostname asd-dev-session` | Your SSH config has no asd-dev entries. Run setup again; on Windows run `setup.cmd`. |
| `asd-dev: ERROR: no session started. Run ./asd-dev start ...` | Your last session ended less than 3 hours ago (the next lines say how). Run `./asd-dev start`. |
| `Disk quota exceeded` in your home | VS Code keeps its server (about 1.3 GB per VS Code version) in `~/.vscode-server`, in your 20 GiB home. Delete old versions there. |
| `Cannot connect to the Docker daemon` | Docker is still starting (restoring saved state can take minutes). See `asd-dev logs`. |

If a saved docker state cannot be restored because it is damaged, the session says so, starts
docker empty and leaves the file alone. `./asd-dev start --reset-docker-state` (stop the running
session first) moves it aside as `<file>.old-<date>` and starts fresh; after two failed restores
in a row this happens by itself. `--no-docker-state` starts one session without restoring or
saving anything and leaves the file untouched. The files are in
`/mnt/wato-drive/slurm-docker-sessions/<uid>/`: `slurm-docker-state.tar.zst` for the default
session, `slurm-docker-state-<name>.tar.zst` for named ones (installs made with
`setup --cluster-dir` add their directory name). A state moved aside is kept as
`<file>.old-<date>`; the two newest such copies are kept, older ones are deleted.

To undo setup, delete the lines between `# >>> asd-dev` and `# <<< asd-dev` in your SSH config and
the `~/.asd-dev` folder in your cluster home.

## How it works

`asd-dev-session` is an SSH host whose `ProxyCommand` logs in to `wato-login1` and runs
`~/.asd-dev/bin/asd-dev proxy`. That helper looks up your session job with `squeue --me`
(submitting one with `sbatch` if there is none), waits until the job's own `sshd` is listening,
and connects VS Code's SSH stream to it. The job runs `sshd` as you on a free port, accepting
the keys registered in your WATcloud profile, with a host key kept in `~/.asd-dev`. VS Code's
server and terminals therefore run inside the job and use its resources.

## Coming from the old scripts

`start_interactive_session.sh`, `session_config.sh` and `ssh_helpers/setup_slurm_ssh.sh` are
replaced by `setup.sh` and `asd-dev`. Setup reuses the username and key from your
`session_config.sh` and offers to comment out the old `asd-dev-session` entry in your SSH
config. You no longer need `~/.ssh/authorized_keys` on the cluster, a port number, or a terminal
kept open for the job. A session started by the old script still works with the new setup.
