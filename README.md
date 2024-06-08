# WATO ASD Tooling
A plethora of bash scripts that will be useful to developers at WATonomous.

# How to Use
```bash
git clone git@github.com:WATonomous/wato_asd_tooling.git
cd wato_asd_tooling
bash <whatever_the_script_to_use>
```

# Directory of Scripts
`ssh_helpers/configure_agent_forwarding.sh` **[RUN ON YOUR LOCAL MACHINE]** Configures your agent forwarding according to [the steps here](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding). This is helpful for when you want to use GitHub in the server. [more](#generate-ssh-configuration)

`ssh_helpers/generate_ssh_config.sh` **[RUN ON YOUR LOCAL MACHINE]** Generates, and optionally appends, an SSH Configuration to your ~/.ssh/config. [more](#generate-ssh-configuration)

`slurm_presets/small_dev_node.sh`

`slurm_presets/medium_dev_node.sh`

`slurm_presets/large_dev_node.sh`

# Descriptions
Provides a better explanation of what the script does.

## Configure Agent Forwarding
`ssh_helpers/configure_agent_forwarding.sh` 

Takes in your SSH private key path and adds it to the SSH Agent. To troubleshoot, please refer to the (actual docs to do agent forwarding)[https://docs.github.com/en/authentication/connecting-to-github-with-ssh/using-ssh-agent-forwarding]. This script was tested with Linux and Mac.

## Generate SSH Configuration
`ssh_helpers/generate_ssh_config.sh`

Takes in your WATcloud username as well as a path to your SSH private key to generate an SSH Configuration to connect to all of our available machines on WATcloud.

We do a proxyjump from the wato bastion to the specific host computer you want to connect to. The configuration also enable AgentForwarding so that you can you GitHub and other things inside the WATcloud machines. 

Agent forwarding will not work properly unless if you [add your key properly](#configure-agent-forwarding). 