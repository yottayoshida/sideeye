#!/bin/sh
set -eu
export GNUPGHOME=/w/gnupg PASSWORD_STORE_DIR=/w/pstore
mkdir -p "$GNUPGHOME" /w/out; chmod 700 "$GNUPGHOME"
if [ ! -f /w/gnupg/done ]; then
  gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key 'sideeye test' default default never >/dev/null 2>&1
  touch /w/gnupg/done
fi
KEY=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')
rm -rf "$PASSWORD_STORE_DIR"; pass init "$KEY" >/dev/null
printf 'x\nx\n' | pass insert ada >/dev/null 2>&1
strace -f -y -e 'trace=%file,%desc,%process,setsid,setpgid' -o /w/out/pass.strace pass mv ada grace >/dev/null 2>&1 || echo "pass mv rc=$?"
echo "--- writers into the store, and the wait windows around them ---"
grep -nE "clone|wait4|exited with|pstore/(store|\.gpg-id)" /w/out/pass.strace | grep -vE "openat.*O_RDONLY|newfstatat|faccessat|statx|readlink" | head -60
