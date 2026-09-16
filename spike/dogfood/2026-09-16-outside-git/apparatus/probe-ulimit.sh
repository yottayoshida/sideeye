#!/bin/sh
# Without Sideeye: each FAIL's rewrite made to fail with a file-size limit, so a reader can see the
# loss with nothing but the tool installed. A write past `ulimit -f` fails with EFBIG (or kills with
# SIGXFSZ where the runtime does not ignore it) after the truncating open, before any byte lands.
# dash counts `ulimit -f` in 512-byte blocks.
set -u
X=/localrun/probe
export HOME=$X/home TMPDIR=$X/tmp XDG_STATE_HOME=$X/state JBANG_NO_VERSION_CHECK=true
mkdir -p "$HOME" "$TMPDIR" "$XDG_STATE_HOME"

echo "== aws-cli $(aws --version 2>&1 | cut -d' ' -f1), ulimit -f 0"
A=$X/aws; mkdir -p $A
printf '[default]\nregion = us-east-1\n' > $A/config
printf '[default]\naws_access_key_id = FAKE-ID-DEFAULT-0001\naws_secret_access_key = fake-secret-default-for-probe-only-000000\n\n[work]\naws_access_key_id = FAKE-ID-WORK-0000001\naws_secret_access_key = fake-secret-work-for-probe-only-00000000\n' > $A/credentials
echo "  before: credentials $(wc -c < $A/credentials) bytes"
( ulimit -f 0; AWS_CONFIG_FILE=$A/config AWS_SHARED_CREDENTIALS_FILE=$A/credentials aws configure set aws_secret_access_key rotated --profile work ) > $X/aws.out 2>&1; rc=$?
echo "  rc=$rc  after: credentials $(wc -c < $A/credentials) bytes"; tail -2 $X/aws.out | sed 's/^/  | /'

echo "== neovim $(nvim --version | head -1), ulimit -f 0"
V=$X/nvim; mkdir -p $V
printf 'call histadd("cmd", "echo first")\ncall setreg("a", "first register")\nwshada!\nqa!\n' > $X/setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > $X/op.vim
nvim --headless -n -u NONE -i $V/main.shada -S $X/setup.vim
echo "  before: main.shada $(wc -c < $V/main.shada) bytes"
( ulimit -f 0; nvim --headless -n -u NONE -i $V/main.shada -S $X/op.vim ) > $X/nvim.out 2>&1; rc=$?
echo "  rc=$rc  after: $(ls $V | tr '\n' ' ')— main.shada $( [ -f $V/main.shada ] && wc -c < $V/main.shada || echo absent) bytes"; tail -3 $X/nvim.out | sed 's/^/  | /'

echo "== jbang 0.141.0 config set (the JVM named directly, -XX:-UsePerfData), ulimit -f 0"
J=$X/jbang; mkdir -p $J
JBANG_DIR=$J java -jar /opt/jbang-0.141.0/bin/jbang.jar config set first.key first-value > /dev/null 2>&1
echo "  before: jbang.properties $(wc -c < $J/jbang.properties) bytes"
( ulimit -f 0; JBANG_DIR=$J java -XX:-UsePerfData -jar /opt/jbang-0.141.0/bin/jbang.jar config set second.key second-value ) > $X/jbang.out 2>&1; rc=$?
echo "  rc=$rc  after: jbang.properties $(wc -c < $J/jbang.properties) bytes"; tail -2 $X/jbang.out | sed 's/^/  | /'

echo "== pyenv $(pyenv --version | cut -d' ' -f2) global, ulimit -f 0"
P=$X/pyenv; mkdir -p $P/versions/3.11.9/bin $P/versions/3.12.4/bin
PYENV_ROOT=$P pyenv global 3.11.9
echo "  before: version $(wc -c < $P/version) bytes"
( ulimit -f 0; PYENV_ROOT=$P pyenv global 3.12.4 ) > $X/pyenv.out 2>&1; rc=$?
echo "  rc=$rc  after: version $(wc -c < $P/version) bytes; pyenv version-name: $(PYENV_ROOT=$P pyenv version-name 2>&1)"; tail -2 $X/pyenv.out | sed 's/^/  | /'
