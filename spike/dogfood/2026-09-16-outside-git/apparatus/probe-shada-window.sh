#!/bin/sh
# The window between `unlink(main.shada)` and `rename(main.shada.tmp.a, main.shada)`, entered for real
# rather than built by hand: strace injects SIGKILL into nvim at its first `renameat`, which follows
# the unlink. Then two ordinary sessions, each recording what it read, its own message history
# (`:messages`) and everything it printed. Both binaries. No Sideeye.
#   (The second review of this record: probe-shada-after.sh part B built the world with the complete
#   new file as the temporary, which is 0.12.5's state and not 0.10.4's, and kept no session output,
#   so "prints nothing" had nothing behind it.)
set -u
export HOME=/tmp/h XDG_STATE_HOME=/tmp/s; mkdir -p $HOME $XDG_STATE_HOME
printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > /tmp/setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > /tmp/op.vim
printf 'call writefile(["register a: " . getreg("a")] + split(execute("history cmd"), "\\n") + ["-- :messages --"] + split(execute("messages"), "\\n"), "/tmp/session.txt")\nqa!\n' > /tmp/session.vim
for bin in nvim nvim012; do
  echo "== $bin ($($bin --version | head -1))"
  w=/tmp/win-$bin; mkdir -p $w
  $bin --headless -n -u NONE -i $w/main.shada -S /tmp/setup.vim > /dev/null 2>&1
  echo "  setup: $(for f in $(ls $w); do printf '%s(%s bytes) ' $f $(wc -c < $w/$f); done)"
  strace -f -qq -o /tmp/inject-$bin.txt -e trace=unlinkat,renameat,renameat2,write -e inject=renameat:signal=KILL:when=1 \
    $bin --headless -n -u NONE -i $w/main.shada -S /tmp/op.vim > /dev/null 2>&1; rc=$?
  echo "  the operation, SIGKILLed at its first renameat: rc=$rc"
  grep -E 'unlinkat|renameat|write\(|\+\+\+ killed' /tmp/inject-$bin.txt | grep -v 'write(1,\|write(2,' | tail -4 | sed 's/^/    strace: /' | cut -c1-170
  echo "  the world it left: $(for f in $(ls $w); do printf '%s(%s bytes) ' $f $(wc -c < $w/$f); done)"
  for s in 1 2; do
    : > /tmp/session.txt
    $bin --headless -n -u NONE -i $w/main.shada -S /tmp/session.vim > /tmp/session-out.txt 2>&1; rc=$?
    echo "  session $s: rc=$rc, stdout+stderr $(wc -c < /tmp/session-out.txt) bytes; afterwards: $(for f in $(ls $w); do printf '%s(%s) ' $f $(wc -c < $w/$f); done)"
    sed 's/^/    | /' /tmp/session.txt
    [ -s /tmp/session-out.txt ] && sed 's/^/    out: /' /tmp/session-out.txt
  done
done
