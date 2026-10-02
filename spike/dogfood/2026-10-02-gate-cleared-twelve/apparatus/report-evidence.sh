#!/bin/sh
# What the two upstream reports quote, run as the reports' own steps: the tool's version, the
# no-kill reproduction with `ulimit -f 0` in a fresh directory, and the write path as strace
# printed it for the one file. Every command is echoed.
#
#   sh report-evidence.sh helm|tombi      (tombi: the v1.7.0 release mounted over /opt/bin/tombi)
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
case "$1" in
helm)
    run 'helm version'
    rm -rf /demo && mkdir -p /demo && cd /demo
    cat > repositories.yaml <<'Y'
apiVersion: ""
generated: "0001-01-01T00:00:00Z"
repositories:
- name: a
  url: https://a.example.invalid/charts
- name: b
  url: https://b.example.invalid/charts
Y
    run 'wc -c < repositories.yaml'
    run '( ulimit -f 0; helm repo remove b --repository-config repositories.yaml --repository-cache cache ); echo "exit $?"'
    run 'wc -c < repositories.yaml; ls -lA'
    echo; echo "## the same command without the limit, under strace, the repositories file only"
    cat > repositories.yaml <<'Y'
apiVersion: ""
generated: "0001-01-01T00:00:00Z"
repositories:
- name: a
  url: https://a.example.invalid/charts
- name: b
  url: https://b.example.invalid/charts
Y
    run 'strace -f -y -e trace=openat,write,rename,renameat,renameat2,ftruncate -P /demo/repositories.yaml helm repo remove b --repository-config repositories.yaml --repository-cache cache 2>&1 | grep -v -E "O_RDONLY|^\[pid +[0-9]+\] \+\+\+|^\+\+\+|SIGURG|resumed" | cut -c1-200'
    run 'wc -c < repositories.yaml; cat repositories.yaml'
    ;;
tombi)
    run 'tombi --version'
    rm -rf /demo && mkdir -p /demo && cd /demo
    printf '[a]\nb=1\nc   =  "x"\n[d]\ne=[1,2,   3]\n' > a.toml
    run 'wc -c < a.toml'
    run '( ulimit -f 0; tombi format --offline a.toml ); echo "exit $?"'
    run 'wc -c < a.toml; ls -lA'
    echo; echo "## the same command without the limit, under strace, that file only"
    printf '[a]\nb=1\nc   =  "x"\n[d]\ne=[1,2,   3]\n' > a.toml
    run 'strace -f -y -e trace=openat,write,rename,renameat,renameat2,ftruncate -P /demo/a.toml tombi format --offline a.toml 2>&1 | grep -v -E "^\[pid +[0-9]+\] \+\+\+|^\+\+\+|resumed" | cut -c1-200'
    run 'wc -c < a.toml; cat a.toml'
    ;;
esac
