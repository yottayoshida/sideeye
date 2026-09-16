#!/bin/sh
# Before any exploration: every checker passes on the setup's state and on the completed
# operation's state, and fails on the state file emptied. The checkers and setups are
# materialised by explore.sh itself (run with a name that matches no target), so what is probed
# is what the explorations run. No Sideeye.
set -u
ONLY=" none " sh /hostap/explore.sh > /dev/null 2>&1
AP=/localrun/ap
export HOME=/localrun/aux/home TMPDIR=/localrun/aux/tmp XDG_STATE_HOME=/localrun/aux/state \
       XDG_DATA_HOME=/localrun/aux/data XDG_CACHE_HOME=/localrun/aux/cache JBANG_NO_VERSION_CHECK=true
mkdir -p "$HOME" "$TMPDIR" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
probe() {  # probe <name> <setup> <check> <state file> <op...>
  name=$1; setup=$2; chk=$3; file=$4; shift 4
  SD=/localrun/probe/$name; export SD; mkdir -p "$SD"
  "$AP/$setup" > /dev/null 2>&1; echo "== $name  setup rc=$?"
  "$AP/$chk" > /tmp/c.txt 2>&1; echo "  after setup:     check rc=$? $(head -1 /tmp/c.txt)"
  ( set -f; eval "$(printf '%s' "$*" | sed "s|@SD@|$SD|g")" ) > /tmp/op.txt 2>&1; echo "  operation rc=$? ($(wc -c < "$SD/$file") bytes in $file)"
  "$AP/$chk" > /tmp/c.txt 2>&1; echo "  after operation: check rc=$? $(head -1 /tmp/c.txt)"
  cp "$SD/$file" /tmp/before-check; "$AP/$chk" > /dev/null 2>&1; cmp -s "$SD/$file" /tmp/before-check && echo "  the check left $file unchanged" || echo "  the check CHANGED $file"
  : > "$SD/$file"
  "$AP/$chk" > /tmp/c.txt 2>&1; echo "  $file emptied:   check rc=$? $(head -1 /tmp/c.txt | cut -c1-160)"
}
probe aws   setup-aws.sh        check-aws.sh   credentials  'env AWS_CONFIG_FILE=@SD@/config AWS_SHARED_CREDENTIALS_FILE=@SD@/credentials aws configure set aws_secret_access_key fake-secret-rotated-for-probe-only-0000 --profile work'
probe hatch setup-hatch.sh      check-hatch.sh config.toml  'env HATCH_CONFIG=@SD@/config.toml hatch config set terminal.styles.info italic'
probe nvim  setup-nvim.sh       check-nvim.sh  main.shada   'nvim --headless -n -u NONE -i @SD@/main.shada -S /localrun/aux/nvim-op.vim'
probe jbang setup-jbang-java.sh check-jbang.sh jbang.properties 'env JBANG_DIR=@SD@ java -jar /opt/jbang-0.141.0/bin/jbang.jar config set second.key second-value'
probe pyenv setup-pyenv.sh      check-pyenv.sh version      'env PYENV_ROOT=@SD@ pyenv global 3.12.4'
echo "== hatch's default [terminal.styles] (the operation must change a value; the first probe set info to bold, the default)"
SD=/localrun/probe/hatch-default; mkdir -p $SD; : > $SD/config.toml; HATCH_CONFIG=$SD/config.toml hatch config restore > /dev/null 2>&1; grep -n -A6 '\[terminal.styles\]' $SD/config.toml | head -8
