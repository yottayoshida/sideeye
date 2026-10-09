#!/bin/sh
# 2026-09-16's checker v2 for nvim-nightly: nvim reads main.shada (through -i, 'shada' cleared before quitting so
# nothing is written back) and reports register a and the command-line history; any E57x is a failure,
# and so is a missing register or a missing "echo first" history entry.
f="$SIDEEYE_STATE_DIR/main.shada"
: > /tmp/nvim-check.txt
printf 'call writefile([getreg("a")] + split(execute("history cmd"), "\\n"), "/tmp/nvim-check.txt")\nset shada=\nqa!\n' > /tmp/nvim-check.vim
nvim-nightly --headless -n -u NONE -i "$f" -S /tmp/nvim-check.vim > /tmp/nvim-check.err 2>&1
what="$( [ -f "$f" ] && echo "$(wc -c < "$f") bytes" || echo "absent; files: $(ls "$SIDEEYE_STATE_DIR" | tr '\n' ' ')")"
if grep -q 'E57[0-9]' /tmp/nvim-check.err; then echo "nvim reports $(grep -o 'E57[0-9][^.]*' /tmp/nvim-check.err | head -1 | cut -c1-90) (main.shada $what)"; exit 1; fi
[ "$(sed -n 1p /tmp/nvim-check.txt)" = "first register" ] || { echo "register a is lost (main.shada $what)"; exit 1; }
sed -n '2,$p' /tmp/nvim-check.txt | grep -q 'echo first' || { echo "the 'echo first' history entry is lost (main.shada $what)"; exit 1; }
exit 0
