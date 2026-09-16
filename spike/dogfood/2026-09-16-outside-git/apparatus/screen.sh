#!/bin/sh
# 2026-09-16 outside-git screen. Six candidates whose state is data a user keeps outside
# version control, each pointed at a state directory through the tool's own variable:
#   aws-cli      AWS_CONFIG_FILE / AWS_SHARED_CREDENTIALS_FILE   `aws configure set` on credentials
#   hatch        HATCH_CONFIG                                     `hatch config set`
#   neovim       -i <shada>                                       history added, `:wshada`
#   jbang        JBANG_DIR                                        `jbang config set`
#   bitwarden    BITWARDENCLI_APPDATA_DIR                         `bw config server`
#   pyenv        PYENV_ROOT                                       `pyenv global`
# Instruments as in the 2026-09-16 crossed-walls run: strace -f -y read by screen-strace.py
# (threads, processes, setsid/setpgid, which tids wrote the state), then `sideeye preflight
# --oracle strace` under the released v1.4.0 and main 047592d, both observation modes. As root
# in a --privileged container, state and work on the container's filesystem (#528).
#
# The operation is split on spaces with no quoting, the way the engine splits `--operation`
# (docs/cli.md), for the strace run as well: the first pass ran strace under `sh -c`, which
# honoured quotes the engine does not, and neovim's quoted `-c` commands reached nvim as loose
# words under the engine and left it waiting for input — ten minutes before it was stopped.
# neovim's commands are a script file now (-S), and every preflight runs under `timeout 600`
# (status 124 when it fires).
#
#   docker run --rm --privileged --network none \
#     -v <v1.4.0 tarball dir>:/se140:ro -v <main build prefix>:/semain:ro \
#     -v <this dir>:/hostap:ro -v <out>:/out sideeye-dogfood:2026-09-16-outside sh /hostap/screen.sh
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/screen
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
cp /hostap/screen-strace.py "$AP/"
export HOME=$AUX/home TMPDIR=$AUX/tmp XDG_STATE_HOME=$AUX/state XDG_DATA_HOME=$AUX/data \
       XDG_CACHE_HOME=$AUX/cache NG_CLI_ANALYTICS=false JBANG_NO_VERSION_CHECK=true
mkdir -p "$HOME" "$TMPDIR" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

/se140/sideeye version
/semain/bin/sideeye version
{ aws --version; hatch --version; nvim --version | head -1; jbang version; bw --version; pyenv --version; } 2>&1 | sed 's/^/  /'
echo

########## setups: each reads $SD ##########
cat > "$AP/setup-aws.sh" <<'EOX'
#!/bin/sh
# Two profiles with (fake) keys; the operation rotates the second profile's secret.
set -eu
mkdir -p "$SD"
printf '[default]\nregion = us-east-1\noutput = json\n\n[profile work]\nregion = eu-west-1\n' > "$SD/config"
printf '[default]\naws_access_key_id = FAKE-ID-DEFAULT-0001\naws_secret_access_key = fake-secret-default-for-probe-only-000000\n\n[work]\naws_access_key_id = FAKE-ID-WORK-0000001\naws_secret_access_key = fake-secret-work-for-probe-only-00000000\n' > "$SD/credentials"
EOX

cat > "$AP/setup-hatch.sh" <<'EOX'
#!/bin/sh
# `hatch config restore` refuses a config path that does not exist yet (the first pass), so the
# file is created empty first.
set -eu
mkdir -p "$SD"
: > "$SD/config.toml"
HATCH_CONFIG="$SD/config.toml" hatch config restore > /dev/null
EOX

cat > "$AP/setup-nvim.sh" <<'EOX'
#!/bin/sh
# A shada file holding one earlier command-line history entry and a register.
set -eu
mkdir -p "$SD"
printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > /localrun/aux/nvim-setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > /localrun/aux/nvim-op.vim
nvim --headless -n -u NONE -i "$SD/main.shada" -S /localrun/aux/nvim-setup.vim > /dev/null 2>&1
EOX

cat > "$AP/setup-jbang.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
JBANG_DIR="$SD" jbang config set first.key first-value > /dev/null 2>&1
EOX

cat > "$AP/setup-bw.sh" <<'EOX'
#!/bin/sh
set -eu
mkdir -p "$SD"
BITWARDENCLI_APPDATA_DIR="$SD" bw config server https://first.example.invalid > /dev/null 2>&1
EOX

cat > "$AP/setup-pyenv.sh" <<'EOX'
#!/bin/sh
# Two installed versions faked as directories, 3.11.9 the global one.
set -eu
mkdir -p "$SD/versions/3.11.9/bin" "$SD/versions/3.12.4/bin"
PYENV_ROOT="$SD" pyenv global 3.11.9
EOX
chmod 755 "$AP"/*.sh

########## the screen ##########
screen() {  # screen <name> <setup> <op template>
  name=$1; setup=$2; optmpl=$3
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  echo "==================== $name ===================="
  SD="$R/st/strace/$name"; export SD
  "$AP/$setup" > "$OUT/$name.setup.txt" 2>&1 || echo "  setup rc=$? (see $name.setup.txt)"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  echo "  operation: $op"
  (cd "$SD" && set -f && strace -f -y -qq -o "$OUT/$name.strace" $op > "$OUT/$name.op.txt" 2>&1)
  echo "  operation rc=$?  ($(wc -l < "$OUT/$name.strace") strace lines); files: $(cd "$SD" && find . -type f | sort | tr '\n' ' ' | cut -c1-200)"
  python3 "$AP/screen-strace.py" "$OUT/$name.strace" "$SD"
  for b in 140 main; do
    case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;;
               main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
    for mode in wrappers syscalls; do
      SD="$R/st/$b-$mode/$name"; export SD
      W="$R/wk/$b-$mode/$name"; mkdir -p "$SD" "$W"
      op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
      (cd "$SD" && timeout 600 "$SE" preflight --state "$SD" --setup "$AP/$setup" --operation "$op" \
        --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --work "$W" \
        > "$OUT/$name.$b.$mode.txt" 2>&1)
      rc=$?
      printf '  %-4s %-8s rc=%s  ' "$b" "$mode" "$rc"
      grep -m1 -E '^(UNKNOWN|PREFLIGHT|SETUP|recording)' "$OUT/$name.$b.$mode.txt" | tr -s ' ' | cut -c1-150
      grep -m2 -E 'threads? of process|divergence at operation|^processes' "$OUT/$name.$b.$mode.txt" \
        | sed -E 's/^ +/        /' | cut -c1-320
    done
  done
  echo
}

screen aws   setup-aws.sh   'env AWS_CONFIG_FILE=@SD@/config AWS_SHARED_CREDENTIALS_FILE=@SD@/credentials aws configure set aws_secret_access_key fake-secret-rotated-for-probe-only-0000 --profile work'
screen hatch setup-hatch.sh 'env HATCH_CONFIG=@SD@/config.toml hatch config set terminal.styles.info bold'
# (bold is hatch's default for this key, so this screen's operation rewrote the file without
# changing a value; explore.sh sets italic)
screen nvim  setup-nvim.sh  'nvim --headless -n -u NONE -i @SD@/main.shada -S /localrun/aux/nvim-op.vim'
screen jbang setup-jbang.sh 'env JBANG_DIR=@SD@ jbang config set second.key second-value'
screen bw    setup-bw.sh    'env BITWARDENCLI_APPDATA_DIR=@SD@ bw config server https://second.example.invalid'
screen pyenv setup-pyenv.sh 'env PYENV_ROOT=@SD@ pyenv global 3.12.4'
