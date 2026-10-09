set -eu
rm -rf /s/glfs /s/glfs-in && mkdir -p /s/glfs /s/glfs-in
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[core]\n\teditor = vi\n' > /s/glfs/gitconfig
