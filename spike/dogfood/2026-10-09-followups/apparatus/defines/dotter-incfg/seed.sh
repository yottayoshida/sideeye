set -eu
# 2026-10-03's dotter define with its configuration moved inside --state: dotter writes .dotter/cache.toml
# and .dotter/cache/ beside its configuration (transcripts/dotter-twice.txt), and the restore rebuilds
# only what is under --state, so with the configuration outside it a later world read a cache saying the
# files were deployed and took another path (kill_did_not_land, the next step's "a cache kept beside the
# configuration").
rm -rf /s/dotter && mkdir -p /s/dotter/home /s/dotter/cfg/.dotter
printf '[default.files]\nbashrc = { target = "/s/dotter/home/.bashrc", type = "template" }\ngitconfig = { target = "/s/dotter/home/.gitconfig", type = "template" }\n' > /s/dotter/cfg/.dotter/global.toml
printf 'packages = ["default"]\n' > /s/dotter/cfg/.dotter/local.toml
printf 'export EDITOR=vim\n' > /s/dotter/cfg/bashrc
printf '[user]\n\tname = me\n' > /s/dotter/cfg/gitconfig
printf '# hand edited\nexport PATH=$HOME/bin:$PATH\n' > /s/dotter/home/.bashrc
printf '[user]\n\tname = old\n' > /s/dotter/home/.gitconfig
