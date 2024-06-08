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

## SLURM Dev Templates
Creates an Interactive VSCode inside a SLURM node with docker already installed. You can use the vscode docker extension inside. Also, images persist between SLURM jobs.

`slurm_templates/small_dev_node.sh` Small SLURM Node with 4CPUs, 16GB RAM, and 10G Tmpdisk. (6hr time limit)

`slurm_templates/medium_dev_node.sh` Small SLURM Node with 8CPUs, 32GB RAM, and 10G Tmpdisk. (4hr time limit)

`slurm_templates/large_dev_node.sh` Small SLURM Node with 16CPUs, 64GB RAM, 10GB VRAM, and 10G Tmpdisk. (3hr time limit)

`slurm_templates/custom_dev_node.sh` Custom SLURM Node which prompts you for all the resources you want. (Upper time limit 1day)

## SLURM Job Templates
Creates a SLURM Job for long running tasks. These are non-interactive, but people will love you for not hogging precious resources while you go out for lunch.

`slurm_templates/custom_job_node.sh` Runs a docker command as a SLURM Job. Prompts you for the resources you need. (Upper time limit 7days).

# Descriptions
Provides a better explanation of what the scripts do.

## Configure Agent Forwarding
`ssh_helpers/configure_agent_forwarding.sh` 

Takes in your SSH private key path and adds it to the SSH Agent. To troubleshoot, please refer to the (actual docs to do agent forwarding)[https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding]. This script was tested with Linux and Mac.

## Generate SSH Configuration
`ssh_helpers/generate_ssh_config.sh`

Takes in your WATcloud username as well as a path to your SSH private key to generate an SSH Configuration to connect to all of our available machines on WATcloud.

We do a proxyjump from the wato bastion to the specific host computer you want to connect to. The configuration also enable AgentForwarding so that you can you GitHub and other things inside the WATcloud machines. 

Agent forwarding will not work properly unless if you [add your key properly](#configure-agent-forwarding). 