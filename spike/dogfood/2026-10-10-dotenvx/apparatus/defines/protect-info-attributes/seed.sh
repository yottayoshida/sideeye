set -eu
rm -rf /s/repo && git init -q /s/repo && cd /s/repo
git config --local filter.dotenvx.clean 'dotenvx precommit --clean %f' && git config --local filter.dotenvx.required true
printf '*.psd binary\nvendor/** linguist-vendored\n.env* filter=dotenvx\n*.env filter=dotenvx\n' > .git/info/attributes
