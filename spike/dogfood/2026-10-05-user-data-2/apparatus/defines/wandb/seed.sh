set -eu
rm -rf /s/wb && mkdir -p /s/wb/wandb
printf '[default]\nmode = online\nproject = soil-survey\nentity = fieldlab\n' > /s/wb/wandb/settings
