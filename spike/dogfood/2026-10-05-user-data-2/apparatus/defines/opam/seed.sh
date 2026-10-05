set -eu
rm -rf /s/opam /s/opam-in /s/opam-repo && mkdir -p /s/opam-in /s/opam-repo/packages
printf 'opam-version: "2.0"\n' > /s/opam-repo/repo
OPAMROOT=/s/opam opam init --bare -n --disable-sandboxing default /s/opam-repo > /s/opam-in/init.log 2>&1
test -s /s/opam/config
