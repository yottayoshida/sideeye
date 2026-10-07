set -eu
rm -rf /s/broot /s/broot-in && mkdir -p /s/broot/home /s/broot-in
printf '# my bashrc\nexport EDITOR=vi\nalias ll="ls -l"\nPS1="\\u@\\h \\w$ "\n' > /s/broot/home/.bashrc
test -s /s/broot/home/.bashrc
