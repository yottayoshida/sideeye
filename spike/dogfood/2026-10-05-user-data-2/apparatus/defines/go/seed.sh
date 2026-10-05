set -eu
rm -rf /s/goenv /s/goenv-in && mkdir -p /s/goenv /s/goenv-in
/opt/go127/go/bin/go telemetry off > /s/goenv-in/seed.log 2>&1
GOENV=/s/goenv/env /opt/go127/go/bin/go env -w GOPROXY=https://proxy.example.internal,direct GOPRIVATE=git.example.internal/* GONOSUMDB=git.example.internal/* >> /s/goenv-in/seed.log 2>&1
test -s /s/goenv/env
