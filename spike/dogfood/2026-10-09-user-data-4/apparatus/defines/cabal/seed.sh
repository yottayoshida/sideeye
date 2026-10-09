set -eu
# cabal's user config written by `cabal user-config init`, then one hand edit a user would make;
# `user-config update` renames it to config.backup and renames a new file in from TMPDIR (lab 10).
rm -rf /s/aux/home/.config/cabal /s/aux/home/.cabal /s/cab && mkdir -p /s/cab
cabal user-config init > /s/cab-seed.log 2>&1
printf -- '-- a line the user added by hand\n' >> /s/aux/home/.config/cabal/config
grep -q 'by hand' /s/aux/home/.config/cabal/config
