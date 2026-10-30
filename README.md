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
helper in your cluster home (`~/.asd-dev`), and adds the hosts `asd-dev-session` and
`asd-dev-login` to the top of your SSH config (`~/.ssh/config`; a backup of the old file is kept
next to it). Run it again at any time to change the username or key.

## 2. Connect

In VS Code, open the **Remote Explorer** in the left bar, pick **SSH**, hover over
**asd-dev-session** and click the arrow ("Connect in Current Window"). Or press F1, run
**Remote-SSH: Connect to Host...** and choose `asd-dev-session`. If VS Code asks for the
platform of the remote host, choose **Linux**.

If you have no session running, connecting starts one with your defaults (4 CPUs, 16 GB RAM,
no GPU, 6 hours). When the cluster has room this takes a few seconds; the first connection
also installs VS Code's server in your cluster home, which takes a minute.

Then open a folder (for example `~/wato_monorepo`) and a terminal. `docker` works there; the
docker daemon may need a few more seconds after the session starts.

If the cluster is busy, VS Code reports that it could not connect. Its log (Output panel,
"Remote - SSH") then has a line starting with `asd-dev:` that says why, for example
`job 123 is waiting for free resources`. The job stays queued; click **Retry** later, or run
`./asd-dev start` in a terminal on your computer, which waits and opens VS Code when the
session is ready.

## 3. Stop

A session stops by itself 60 minutes after the last connection to it closes (closing VS Code,
or your laptop going to sleep), or when its time limit is reached. A running `tmux` or `screen`
keeps it alive while you are disconnected.

To stop it now, run `asd-dev stop` in the VS Code terminal, or `./asd-dev stop` on your computer.
Stopping saves your docker images and containers; the next session restores them. Saved docker
state lives in `/mnt/wato-drive/slurm-docker-sessions/<your uid>/`.

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

GPU types: `rtx_2080_ti`, `rtx_3090`, `rtx_4090`, `gtx_1080`. `tmpdisk` is the job's `/tmp` in MiB,
where docker keeps its images; give it room if you use large images. A running session keeps its
resources; to change them, stop it and start again. The meaning of every setting is in
`~/.asd-dev/config` on the cluster.

## More than one session

Give a session a name: `./asd-dev start gpu --vram 8192`. Connect to it as
`asd-dev-session-gpu` (type that name in **Remote-SSH: Connect to Host...**). Stop it with
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
| `./asd-dev ssh [NAME]` | open a terminal in a session (same as `ssh asd-dev-session`) |

`ssh asd-dev-session` also works in any terminal on your computer, and so do `scp` and `rsync`.

## Troubleshooting

When VS Code cannot connect, open the Output panel (View > Output), pick **Remote - SSH**, and
look for lines starting with `asd-dev:`. Most problems are one of these:

| You see | What to do |
| --- | --- |
| `Permission denied (publickey)` | Wrong username or a key that is not registered. Run setup again; it checks both. |
| `asd-dev: job N is waiting ...` | The cluster is busy. Click Retry later, or run `./asd-dev start` to wait for it. |
| `asd-dev: ... held back by your per-user limit` | Your other jobs use your share (`squeue --me` on the login node). Stop some, or ask for less. |
| `.asd-dev/bin/asd-dev: No such file or directory` | The helper is missing from your cluster home. Run setup again. |
| `Host key verification failed` | The session host key changed (for example `~/.asd-dev` was deleted). Run setup again. |
| `Could not resolve hostname asd-dev-session` | Your SSH config has no asd-dev entries. Run setup again; on Windows run `setup.cmd`. |
| `Cannot connect to the Docker daemon` | Docker is still starting (restoring saved state can take minutes). See `asd-dev logs`. |

If docker misbehaves after a restore, start once without the saved state
(`./asd-dev start --no-docker-state`) or delete the state file in
`/mnt/wato-drive/slurm-docker-sessions/<uid>/`.

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
