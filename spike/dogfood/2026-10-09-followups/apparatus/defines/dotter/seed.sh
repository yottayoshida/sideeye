set -eu
rm -rf /s/dotter /s/dotter-in && mkdir -p /s/dotter/home /s/dotter-in/.dotter
printf '[default.files]\nbashrc = { target = "/s/dotter/home/.bashrc", type = "template" }\ngitconfig = { target = "/s/dotter/home/.gitconfig", type = "template" }\n' > /s/dotter-in/.dotter/global.toml
printf 'packages = ["default"]\n' > /s/dotter-in/.dotter/local.toml
printf 'export EDITOR=vim\n' > /s/dotter-in/bashrc
printf '[user]\n\tname = me\n' > /s/dotter-in/gitconfig
printf '# hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotter/home/.bashrc
printf '[user]\n\tname = old\n' > /s/dotter/home/.gitconfig
