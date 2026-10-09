set -eu
# 2026-09-16 outside-git's neovim define (apparatus/nvim-v2.sh), the shada written and read by nvim-0125.
# main.shada holds register a and the command-line history; the operation adds "echo second" and
# writes it back with :wshada. main.shada is scratch (its bytes carry timestamps, so two clean runs
# differ) and the checker judges it: nvim must read it back with register a and "echo first".
rm -rf /s/nv /s/nv-in && mkdir -p /s/nv /s/nv-in
printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > /s/nv-in/setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > /s/nv-in/op.vim
nvim-0125 --headless -n -u NONE -i /s/nv/main.shada -S /s/nv-in/setup.vim > /dev/null 2>&1
install -m 755 /ap/defines/nvim-0125/check.sh /s/nv-check.sh
[ -s /s/nv/main.shada ]
