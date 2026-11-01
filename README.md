# WATO ASD Tooling: VS Code inside a WATcloud SLURM job

Work in VS Code on your computer while everything runs in a SLURM job on the WATcloud cluster:
the job's CPUs, RAM and GPU, your cluster home, and a working `docker`.

## Before you start

- You know your **cluster username**: "Username" under "Compute Cluster" in your
  [WATcloud profile](https://cloud.watonomous.ca/docs/utilities/profile-editor). It can differ
  from your WATcloud username.
- The SSH key registered in that profile is on this computer (usually `~/.ssh/id_ed25519`).
- You are on campus or on the
  [UW VPN](https://uwaterloo.ca/information-systems-technology/services/virtual-private-network-vpn).
- [VS Code](https://code.visualstudio.com/) and its
  [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
  extension are installed.
- You have this repo: `git clone https://github.com/WATonomous/wato_asd_tooling.git` (or the ZIP).

## Quick start

Run these in a terminal in the `wato_asd_tooling` folder:

- **macOS, Linux:** as shown.
- **Windows (PowerShell or Command Prompt):** type `.\setup.cmd` instead of `./setup.sh` and
  `.\asd-dev.cmd` instead of `./asd-dev`.
- **WSL or Git Bash:** as shown, in that shell. Setup in WSL also sets up Windows, where VS Code
  runs.

1. **Set up once:** `./setup.sh`. It asks for your username and key and checks the login.
   Run it again at any time to change them.
2. **Start a session:** `./asd-dev start`. It waits for the job and opens VS Code in it.
   If the cluster is busy, start says why and keeps waiting. Ctrl-C stops waiting but leaves the
   job queued; `./asd-dev stop` cancels it.
3. **Connect again later:** in VS Code, open **Remote Explorer**, pick **SSH**, and click the
   arrow next to **asd-dev-session**.
4. **Stop:** `./asd-dev stop`. Otherwise the session ends 5 minutes before its time limit
   (6 hours by default), to save docker state. Closing VS Code does not stop it.

Good to know:

- Connecting never starts a session. Start one first.
- The first connection installs VS Code's server in your home (about a minute).
- `./asd-dev start --folder /home/<username>/wato_monorepo` opens that folder directly.
- On Windows, the first connection asks for the remote platform: choose **Linux**. The question
  can hide behind VS Code's welcome dialog.
- In a session's terminal the command is just `asd-dev` (for example `asd-dev stop`).
- Your SSH agent is forwarded into sessions so `git` over SSH works. Run setup with
  `--no-agent-forwarding` if you do not want that.

## Resources

Use these options once with `start`, or save them as your defaults with `config`:

```bash
./asd-dev start --gres shard:8192               # 8 GiB slice of a GPU, this session only
./asd-dev start --gres gpu:rtx_3090:1           # a whole GPU of one type
./asd-dev config --cpus-per-task 8 --mem 32G    # new defaults for every session
./asd-dev config --unset mem                    # back to the built-in default
./asd-dev config                                # show your defaults
```

- Defaults: 4 CPUs, 16G RAM, 6 hours, 10 GiB `/tmp`.
- Other options (`--time`, `--gpus`, `--partition`, `--nodelist`, `--exclude`,
  `--docker-state`, ...): see `./asd-dev --help`.
- `/tmp`, where docker keeps its images, is 10 GiB; ask for more with `--gres tmpdisk:MiB`
  (`watcloud quota disk` in a session shows its use). **CARLA needs `--gres tmpdisk:40960`**;
  with a GPU slice: `--gres tmpdisk:40960,shard:8192`.
- A `--gres` on start replaces the one in your defaults, except that `/tmp` (tmpdisk) is kept
  unless you name it.
- In PowerShell, quote a value with commas: `--gres "tmpdisk:40960,shard:8192"`.
- GPU types: `rtx_2080_ti`, `rtx_3090`, `rtx_4090`, `gtx_1080`. `nvidia-smi` shows the whole
  card; nothing stops you using more than your slice, so don't.
- A running session keeps its resources. To change them, stop it and start again.

## Docker

- `docker` works in the session's terminals. The Docker extension and Dev Containers' **Attach
  to Running Container** should work too.
- A session saves your images and containers when it ends (stop or time limit, not
  `stop --now`); the next session restores them.
- `watod build` should still work without a GHCR login (it builds from the public base image),
  only slower.

The monorepo's images on GHCR are private. To pull them, log in once:

1. Create a GitHub classic personal access token with `read:packages` (`write:packages` only if
   you push).
2. In a session's terminal: `docker login ghcr.io -u <your GitHub username>`.
3. Paste the token at the Password prompt (it isn't shown). Later sessions stay logged in.

## More than one session

- Name it: `./asd-dev start --name carla --gres tmpdisk:40960`. VS Code then lists
  `asd-dev-session-carla`.
- Use the same `--name` with every command, for example `./asd-dev stop --name carla`.
- Without `--name`, commands mean the default session (in a session's terminal: that session).
- Names are lowercase. Each name has its own saved docker state.

## Commands

| Command | What it does |
| --- | --- |
| `./asd-dev start [--name NAME] [options]` | start a session and open VS Code (`--no-code`: don't) |
| `./asd-dev stop [--name NAME]` | stop it (`--now`: without saving docker state; `--all`: every session) |
| `./asd-dev status [--name NAME]` | list your sessions: node, time left, resources |
| `./asd-dev logs [--name NAME]` | show a session's log (`-f` to follow) |
| `./asd-dev config [options]` | show or change your defaults (`--unset OPTION` removes one) |
| `./asd-dev code [--name NAME]` | open VS Code in a running session |
| `./asd-dev add --name NAME` | add the host for a named session to your SSH config |
| `./asd-dev ssh [--name NAME] [command]` | open a terminal in a session (same as `ssh asd-dev-session`) |

`code`, `add` and `ssh` work only on your computer.

## Troubleshooting

VS Code often says only "An unknown error occurred". The reason is in View > Output >
**Remote - SSH**, on lines starting with `asd-dev:`.

| You see | What to do |
| --- | --- |
| `no session 'default' is running` | Start one: `./asd-dev start`. |
| `is still waiting to start` | The cluster is busy. `./asd-dev status` shows why. Connect once it runs. |
| `held back by your per-user limit` | Your other jobs use your share. Stop some, or ask for less. |
| `Connection timed out` | You are off campus without the UW VPN. |
| `Permission denied (publickey)`, `Host key verification failed`, `.asd-dev/bin/asd-dev: No such file` | Run setup again (it checks your username and key). |
| `Could not resolve hostname asd-dev-session-...` | Run `./asd-dev add --name NAME`. |
| `Disk quota exceeded` in your home | Delete old VS Code versions in `~/.vscode-server` (about 1.3 GB each). |
| `Cannot connect to the Docker daemon` | Docker is still starting. Wait, or see `./asd-dev logs`. |
| `no space left on device` (docker) | `/tmp` is full. `docker system prune`, or start with a bigger `--gres tmpdisk:...`. |

If the saved docker state cannot be restored:

- Docker starts empty, the saved file is kept, and this session does not save over it.
- Your terminal says what to run: a bigger `--gres tmpdisk:...`, or
  `./asd-dev start --reset-docker-state` to set a damaged file aside and start fresh.

To undo setup, delete the `# >>> asd-dev` ... `# <<< asd-dev` lines from your SSH config and the
`~/.asd-dev` folder in your cluster home.

## Coming from the old scripts

- `start_interactive_session.sh`, `session_config.sh` and `ssh_helpers/` are gone. Use
  `./setup.sh` and `./asd-dev`. Stop a session they started with `scancel <job id>` (`squeue --me`
  on the login node shows it as `wato_slurm_dev`).
- If `git pull` refuses because you edited `session_config.sh`, run
  `git checkout -- session_config.sh` first.
- Setup offers to comment out the old `asd-dev-session` entry in your SSH config.
- Your saved docker state carries over.
