set -eu
# chezmoi's own database lives under $HOME; the 2026-09-27 setup (cz-setup.sh) cleared it before
# every engine run. Here $HOME is /s/chezmoi/home (sideeye.toml declares it), so removing the
# whole tree clears it too. The destination starts empty, as it did then.
rm -rf /s/chezmoi && mkdir -p /s/chezmoi/src /s/chezmoi/dest /s/chezmoi/home
printf 'hello from chezmoi\n' > /s/chezmoi/src/dot_testrc
printf 'second file\n' > /s/chezmoi/src/dot_second
