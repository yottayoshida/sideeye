#!/bin/sh
# The reproduction steps the two upstream drafts carry, run verbatim, so what the drafts print is what
# was printed here. (The first run wrote the strace syscall regex as `/^rename/`, which strace rejects
# as an invalid system call, so nvim never ran under it; the regex is `/^rename` now.) aws-cli on the current official v2 build (awscli-exe-linux-aarch64.zip, mounted at
# /awszip) and on Debian's 2.23.6; neovim on the v0.12.5 release. No Sideeye.
set -u
echo "######## aws-cli"
for AWS in /awszip/aws/dist/aws /usr/bin/aws; do
  d=$(mktemp -d); cd $d
  echo "== $($AWS --version 2>&1)"
  alias_aws() { $AWS "$@"; }
  export AWS_CONFIG_FILE=$PWD/config AWS_SHARED_CREDENTIALS_FILE=$PWD/credentials
  printf '[default]\nregion = us-east-1\n' > config
  printf '[default]\naws_access_key_id = EXAMPLE-ID-1\naws_secret_access_key = example-secret-1\n\n[work]\naws_access_key_id = EXAMPLE-ID-2\naws_secret_access_key = example-secret-2\n' > credentials
  echo "\$ wc -c credentials"; wc -c credentials
  echo "\$ (ulimit -f 0; aws configure set aws_secret_access_key example-secret-3 --profile work); echo \"exit \$?\""
  (ulimit -f 0; $AWS configure set aws_secret_access_key example-secret-3 --profile work); echo "exit $?"
  echo "\$ wc -c credentials"; wc -c credentials
  printf '[default]\naws_access_key_id = EXAMPLE-ID-1\naws_secret_access_key = example-secret-1\n\n[work]\naws_access_key_id = EXAMPLE-ID-2\naws_secret_access_key = example-secret-2\n' > credentials
  echo "\$ strace -f -o /dev/null -P credentials -e inject=write:signal=KILL:when=1 aws configure set aws_secret_access_key example-secret-3 --profile work; echo \"exit \$?\""
  strace -f -o /dev/null -P credentials -e inject=write:signal=KILL:when=1 $AWS configure set aws_secret_access_key example-secret-3 --profile work; echo "exit $?"
  echo "\$ wc -c credentials"; wc -c credentials
  echo "\$ aws configure get aws_access_key_id --profile default; echo \"exit \$?\""
  $AWS configure get aws_access_key_id --profile default; echo "exit $?"
  cd /; unset AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE
done
echo; echo "######## neovim"
d=$(mktemp -d); cd $d; export HOME=$d/home XDG_STATE_HOME=$d/state; mkdir -p $HOME $XDG_STATE_HOME
ln -s /usr/local/bin/nvim012 $d/nvim; PATH=$d:$PATH
echo "== $(nvim --version | head -1)"
cat <<'STEPS' > steps.sh
printf 'call histadd("cmd", "echo first")\nwshada!\nqa!\n' > first.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > second.vim
nvim --headless -n -u NONE -i main.shada -S first.vim
strace -f -o /dev/null -e inject=/^rename:signal=KILL:when=1 \
  nvim --headless -n -u NONE -i main.shada -S second.vim
ls -l main.shada*
nvim --headless -n -u NONE -i main.shada \
  +'call writefile([string(histnr("cmd"))], "/dev/stdout")' +'qa!'
STEPS
cat steps.sh | sed 's/^/$ /'
echo "--- output"
sh steps.sh 2>&1 | sed -E 's/ +[A-Z][a-z]{2} [ 0-9]{2} [0-9:]{4,5} / <date> /'
echo "--- the same, without the kill (the control)"
d2=$(mktemp -d); cd $d2; cp $d/steps.sh .; sed -i 's/^strace -f -o \/dev\/null -e inject=\/\^rename:signal=KILL:when=1 \\$/\\/' steps.sh; head -5 steps.sh | tail -2 | sed 's/^/$ /'
sh steps.sh 2>&1 | sed -E 's/ +[A-Z][a-z]{2} [ 0-9]{2} [0-9:]{4,5} / <date> /'
