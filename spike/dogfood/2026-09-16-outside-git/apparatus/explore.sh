#!/bin/sh
# 2026-09-16 outside-git explore: the five targets the screens accepted.
#   released v1.4.0: aws, hatch, nvim, jbang-java — wrappers x3 and syscalls x1; pyenv — syscalls x3
#   main 047592d (not a release): one explore each, in the first mode above
# As root in a --privileged container, state and work on the container's filesystem (#528).
# Image: Dockerfile. Every explore runs under `timeout 1800` (status 124 when it fires).
#
#   docker run --rm --privileged --network none \
#     -v <v1.4.0 tarball dir>:/se140:ro -v <main build prefix>:/semain:ro \
#     -v <this dir>:/hostap:ro -v <out>:/out sideeye-dogfood:2026-09-16-outside sh /hostap/explore.sh
set -u
R=/localrun
AP=$R/ap
AUX=$R/aux
OUT=/out/explore
mkdir -p "$AP" "$AUX" "$OUT" "$R/wk"
# The screens' setups, materialised by running them with a name that matches no target.
ONLY=" none " sh /hostap/screen.sh > /dev/null 2>&1
ONLY=" none " sh /hostap/screen2.sh > /dev/null 2>&1
export HOME=$AUX/home TMPDIR=$AUX/tmp XDG_STATE_HOME=$AUX/state XDG_DATA_HOME=$AUX/data \
       XDG_CACHE_HOME=$AUX/cache JBANG_NO_VERSION_CHECK=true
mkdir -p "$HOME" "$TMPDIR" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
/se140/sideeye version
/semain/bin/sideeye version

########## checkers: each reads $SD, and each asks the tool itself ##########
cat > "$AP/check-aws.sh" <<'EOC'
#!/bin/sh
# Both profiles' access keys are still readable through the CLI, and the edited secret is either
# the old one or the new one.
export AWS_CONFIG_FILE="$SD/config" AWS_SHARED_CREDENTIALS_FILE="$SD/credentials"
k=$(aws configure get aws_access_key_id --profile default 2>/tmp/aws-e.txt)
[ "$k" = FAKE-ID-DEFAULT-0001 ] || { echo "default profile's access key is \"$k\" ($(wc -c < "$SD/credentials") bytes in credentials): $(head -1 /tmp/aws-e.txt)"; exit 1; }
k=$(aws configure get aws_access_key_id --profile work 2>/dev/null)
[ "$k" = FAKE-ID-WORK-0000001 ] || { echo "work profile's access key is \"$k\""; exit 1; }
s=$(aws configure get aws_secret_access_key --profile work 2>/dev/null)
case "$s" in fake-secret-work-for-probe-only-00000000|fake-secret-rotated-for-probe-only-0000) exit 0 ;; esac
echo "work profile's secret is neither the old nor the new one: \"$s\""; exit 1
EOC

cat > "$AP/check-hatch.sh" <<'EOC'
#!/bin/sh
# hatch can still read its configuration, and the setting is the old value (the default, bold)
# or the new one (italic).
out=$(HATCH_CONFIG="$SD/config.toml" hatch config show 2>&1) || { echo "hatch config show failed: $(printf '%s' "$out" | tail -1)"; exit 1; }
python3 - "$SD/config.toml" <<'PY' || exit 1
import sys, tomllib
try:
    d = tomllib.load(open(sys.argv[1], "rb"))
except Exception as e:
    print("config.toml does not parse:", e); sys.exit(1)
if "mode" not in d or "dirs" not in d:
    print("config.toml lost its content: keys", sorted(d)); sys.exit(1)
v = d.get("terminal", {}).get("styles", {}).get("info")
if v not in ("bold", "italic"):
    print("terminal.styles.info is", repr(v)); sys.exit(1)
PY
EOC

cat > "$AP/check-nvim.sh" <<'EOC'
#!/bin/sh
# The shada file still holds what the setup put there — the command-line history entry and
# register a — read by nvim itself. It reads the file at startup through -i and clears 'shada'
# before quitting, so the check writes nothing back (measured: the file compares equal after).
# `-i NONE` with `:rshada!` read nothing at all (apparatus/probe-checkers.sh, first version).
f="$SD/main.shada"
[ -f "$f" ] || { echo "main.shada is gone ($(ls "$SD" | tr '\n' ' '))"; exit 1; }
: > /tmp/nvim-check.txt
printf 'call writefile([getreg("a"), histget("cmd", 1), histget("cmd", 2)], "/tmp/nvim-check.txt")\nset shada=\nqa!\n' > /tmp/nvim-check.vim
nvim --headless -n -u NONE -i "$f" -S /tmp/nvim-check.vim > /tmp/nvim-check.err 2>&1
grep -q 'first register' /tmp/nvim-check.txt 2>/dev/null || { echo "register a is lost ($(wc -c < "$f") bytes in main.shada): $(head -1 /tmp/nvim-check.err)"; exit 1; }
grep -q 'echo first' /tmp/nvim-check.txt || { echo "the 'echo first' history entry is lost ($(wc -c < "$f") bytes)"; exit 1; }
exit 0
EOC

cat > "$AP/check-jbang.sh" <<'EOC'
#!/bin/sh
# jbang still returns the key the setup stored.
v=$(JBANG_DIR="$SD" java -jar /opt/jbang-0.141.0/bin/jbang.jar config get first.key 2>/tmp/jb-e.txt)
[ "$v" = first-value ] || { echo "config get first.key returned \"$v\" ($(wc -c < "$SD/jbang.properties") bytes): $(head -1 /tmp/jb-e.txt)"; exit 1; }
exit 0
EOC

cat > "$AP/check-pyenv.sh" <<'EOC'
#!/bin/sh
# pyenv still selects one of the two installed versions, not the system Python.
v=$(PYENV_ROOT="$SD" pyenv version-name 2>/tmp/pe-e.txt)
case "$v" in 3.11.9|3.12.4) exit 0 ;; esac
echo "pyenv version-name is \"$v\" ($(wc -c < "$SD/version" 2>/dev/null || echo no) bytes in version): $(head -1 /tmp/pe-e.txt)"; exit 1
EOC
chmod 755 "$AP"/*.sh

########## the driver ##########
ex() {  # ex <build> <mode> <run> <name> <setup> <op template> <check>
  b=$1; mode=$2; i=$3; name=$4; setup=$5; optmpl=$6; chk=$7
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  case $b in 140) SE=/se140/sideeye; SHIM=/se140/libsideeye_shim.so ;;
             main) SE=/semain/bin/sideeye; SHIM=/semain/lib/libsideeye_shim.so ;; esac
  tag="$name.$b.$mode.$i"
  SD="$R/st/$tag"; export SD
  W="$R/wk/$tag"; mkdir -p "$SD" "$W"
  op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
  start=$(date +%s)
  (cd "$SD" && timeout 1800 "$SE" explore --state "$SD" --setup "$AP/$setup" --operation "$op" \
    --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" \
    --work "$W" --json "$OUT/$tag.json" > "$OUT/$tag.txt" 2>&1)
  rc=$?
  printf '%-30s rc=%s %4ss  ' "$tag" "$rc" "$(( $(date +%s) - start ))"
  grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$OUT/$tag.txt" | tr -s ' ' | cut -c1-120
  grep -m3 -E '^ *(earliest|path |observed)' "$OUT/$tag.txt" | tr -s ' ' | sed 's/^/    /' | cut -c1-200
}

AWS_OP='env AWS_CONFIG_FILE=@SD@/config AWS_SHARED_CREDENTIALS_FILE=@SD@/credentials aws configure set aws_secret_access_key fake-secret-rotated-for-probe-only-0000 --profile work'
HATCH_OP='env HATCH_CONFIG=@SD@/config.toml hatch config set terminal.styles.info italic'
NVIM_OP='nvim --headless -n -u NONE -i @SD@/main.shada -S /localrun/aux/nvim-op.vim'
JBANG_OP='env JBANG_DIR=@SD@ java -jar /opt/jbang-0.141.0/bin/jbang.jar config set second.key second-value'
PYENV_OP='env PYENV_ROOT=@SD@ pyenv global 3.12.4'

for i in 1 2 3; do
  ex 140 wrappers $i aws   setup-aws.sh        "$AWS_OP"   check-aws.sh
  ex 140 wrappers $i hatch setup-hatch.sh      "$HATCH_OP" check-hatch.sh
  ex 140 wrappers $i nvim  setup-nvim.sh       "$NVIM_OP"  check-nvim.sh
  ex 140 wrappers $i jbang setup-jbang-java.sh "$JBANG_OP" check-jbang.sh
  ex 140 syscalls $i pyenv setup-pyenv.sh      "$PYENV_OP" check-pyenv.sh
done
ex 140 syscalls 1 aws   setup-aws.sh        "$AWS_OP"   check-aws.sh
ex 140 syscalls 1 hatch setup-hatch.sh      "$HATCH_OP" check-hatch.sh
ex 140 syscalls 1 nvim  setup-nvim.sh       "$NVIM_OP"  check-nvim.sh
ex 140 syscalls 1 jbang setup-jbang-java.sh "$JBANG_OP" check-jbang.sh
ex main wrappers 1 aws   setup-aws.sh        "$AWS_OP"   check-aws.sh
ex main wrappers 1 hatch setup-hatch.sh      "$HATCH_OP" check-hatch.sh
ex main wrappers 1 nvim  setup-nvim.sh       "$NVIM_OP"  check-nvim.sh
ex main wrappers 1 jbang setup-jbang-java.sh "$JBANG_OP" check-jbang.sh
ex main syscalls 1 pyenv setup-pyenv.sh      "$PYENV_OP" check-pyenv.sh
