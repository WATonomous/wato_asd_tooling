# WATO ASD Tooling
A plethora of bash scripts that will be useful to developers at WATonomous.

# How to Use
```bash
git clone git@github.com:WATonomous/wato_asd_tooling.git
cd wato_asd_tooling
bash <whatever_the_script_to_use>
```

# Directory of Scripts
## SSH Helpers
Sets up your local machine to connect with WATcloud.

`ssh_helpers/configure_agent_forwarding.sh` **[RUN ON YOUR LOCAL MACHINE]** Configures your agent forwarding according to [the steps here](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding). This is helpful for when you want to use GitHub in the server. [more](#generate-ssh-configuration)

`ssh_helpers/generate_ssh_config.sh` **[RUN ON YOUR LOCAL MACHINE]** Generates, and optionally appends, an SSH Configuration to your ~/.ssh/config. [more](#generate-ssh-configuration)

`ssh_helpers/setup_slurm_ssh.sh` **[RUN ON YOUR LOCAL MACHINE]** Sets up your pc to connect to slurm dev sessions.

## SLURM Dev Session

`session_config.sh` Configures how you want to run your slurm dev session. This includes what compute resources you need, and your login credentials.

`start_interactive_session.sh` **[RUN ON YOUR LOCAL MACHINE]** Starts an interactive dev session on the WATcloud server. You can then connect to this session via vscode if you already ran `setup_slurm_ssh.sh`

# Descriptions
Provides a better explanation of what the scripts do.

## Configure Agent Forwarding
`ssh_helpers/configure_agent_forwarding.sh` 

Takes in your SSH private key path and adds it to the SSH Agent. To troubleshoot, please refer to the (actual docs to do agent forwarding)[https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding]. This script was tested with Linux and Mac.

## Generate SSH Configuration
`ssh_helpers/generate_ssh_config.sh`

Takes in your WATcloud username as well as a path to your SSH private key to generate an SSH Configuration to connect to all of our available machines on WATcloud. The configuration also enables AgentForwarding so that you can you GitHub and other things inside the WATcloud machines. 
<!-- We do a proxyjump from the wato bastion to the specific host computer you want to connect to. The configuration also enable AgentForwarding so that you can you GitHub and other things inside the WATcloud machines.  -->

Agent forwarding will not work properly unless if you [add your key properly](#configure-agent-forwarding). 
