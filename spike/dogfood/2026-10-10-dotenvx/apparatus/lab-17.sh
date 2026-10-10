#!/bin/sh
# B4 through the real entry: `dotenvx protect` with a terminal (util-linux `script` makes one), the
# "Protect private keys" box unticked by keystrokes (down, space, down, enter), which is what calls
# protectSettings.removeIgnore(). First a control with no fault, to show the prompt was reached and
# the line went; then the same keystrokes with that file's writes failing ENOSPC. 2.34.2.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-dx1010 sh /ap/lab-17.sh
echo "# dotenvx protect, interactive: unticking a protection rewrites the global ignore file"
export PATH=/opt/dx-2.34.2/bin:/usr/local/bin:/usr/bin:/bin npm_config_update_notifier=false TERM=xterm
unset CI
# Down to "Protect private keys", space to untick it, down to the submit row, enter. The first try sent
# down, space, enter: the pty `script` makes takes its size from a pipe, 0 rows, so the prompt drew no
# choices ("No matching choices") and nothing changed; `stty` gives it a size now.
keys() { sleep 4; printf '\033[B'; sleep 1; printf ' '; sleep 1; printf '\033[B'; sleep 1; printf '\r'; sleep 4; }
for how in control ENOSPC; do
  export HOME=/s/lab17/home-$how XDG_CONFIG_HOME=; mkdir -p $HOME/.config/git; git init -q /s/lab17/repo-$how; cd /s/lab17/repo-$how
  ig=$HOME/.config/git/ignore
  printf '*.log\n.DS_Store\n.idea/\n.env.keys*\n' > $ig
  git config --global core.excludesFile $ig; git config --global dotenvx.protect.ignoreFile $ig
  dotenvx protect > /dev/null 2>&1   # the filter half, as a first run would leave it
  echo "## $how: before, $(wc -c < $ig) bytes: $(tr '\n' '|' < $ig)"
  if [ $how = control ]; then cmd="dotenvx protect"
  else cmd="strace -f -qq -o /dev/null -P $ig -e inject=write:error=ENOSPC dotenvx protect"; fi
  keys | script -qec "stty rows 40 cols 120; $cmd" /dev/null > ../out-$how.txt 2>&1; echo "   exit $?"
  echo "   the prompt said: $(tr -d '\033' < ../out-$how.txt | tr '\r\n' '  ' | grep -o 'Set protections[^?]*\|protection: [a-z]*[^)]*)\|ENOSPC[^,]*' | sort -u | tr '\n' ';' | cut -c1-200)"
  echo "   after, $(wc -c < $ig) bytes: $(tr '\n' '|' < $ig)"
done
