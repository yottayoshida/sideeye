# 2026-09-21 release-path: does `docs/ci-quickstart.md`'s adoption procedure work on real
# projects? Copied from 2026-09-16-outside-git/apparatus/Dockerfile, which had already paid for
# the apt-per-candidate shape and the intercepting proxy. Three differences, all deliberate:
#
#   1. **Sideeye is NOT mounted.** Every earlier dogfood run mounted a release tarball the
#      operator had unpacked (`-v <tarball>:/se140:ro`). This one runs the vendored installer the
#      quickstart tells a project to copy, so the engine under test arrives the way a project
#      would get it. That is the whole point of the run.
#   2. **`curl` is added.** `python3` and `ca-certificates` were already here. Plain
#      `debian:trixie-slim` has `tar` and `sha256sum` but not `curl` or `python3`, measured —
#      this is the container making up for not being a GitHub runner, which has all four. It is
#      not a gap in the procedure.
#   3. **The install needs the network; the explores do not.** The install happens here, at build
#      time, where there is a network. `explore.sh` still runs `--network none`.
#
# **The intercepting proxy, and why the CA is here.** This machine's containers are behind
# Netskope: `curl` to anything returns `(60) SSL certificate problem: self-signed certificate in
# certificate chain`, and the certificate offered for api.github.com is issued by
# the corporate proxy's own CA rather than by a public one. Measured with a control in the same
# run — `https://example.com` fails identically — so the installer is not what is broken. The CA is copied in so the
# installer can do what it is for: fetch the release and check it against the digest GitHub
# publishes. **This is the one place the container stops being a faithful stand-in for a
# GitHub runner**, and RESULTS.md says so rather than letting the green build imply otherwise.
#
# apt lists are not cleaned (omamori blocks the rm -rf string on the host side).
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 python3-venv ca-certificates unzip procps bash git curl

# The proxy's CA, staged beside this file by `build.sh` and gitignored: Docker Desktop will not
# share /Library, so it cannot be mounted from where the agent keeps it, and a public repository
# is the wrong place for this machine's network configuration.
COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

# The candidates, each alone so a missing package prints MISSING rather than failing the build.
RUN for p in rbenv nodejs npm golang-go; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

# ---- the adoption step under test ---------------------------------------------------------
#
# Exactly what `docs/ci-quickstart.md` tells a project to do: copy the script, run it with a
# version and a directory. Nothing else is done to it.
#
# **stdout and stderr are split and both kept.** The page claims stdout is the binary's absolute
# path and nothing else; a `RUN` mixes the two in the build log, so the claim could not be
# checked from there. `/install.path` and `/install.log` are the evidence, and explore.sh reads
# the first of them rather than hard-coding a path — so a verdict can be tied to the binary this
# step produced. The report carries no engine version (only `contract_version`, which a local
# build shares), so this file trail is the only thing that ties the two together.
COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.5.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

WORKDIR /w
