# 2026-09-21 verdict-chain: the follow-up to the release-path run, which spent its only
# target slot on a statically linked binary and stopped at `attempted`.
#
# Copied from 2026-09-21-release-path/apparatus/Dockerfile, which had already paid for the
# vendored-installer shape and the intercepting proxy. What is the same, and deliberately:
#
#   * **Sideeye is NOT mounted.** The vendored `install-sideeye.sh` runs here, at build
#     time, so the engine under test arrives the way `docs/ci-quickstart.md` tells a
#     project to get it. The explores still run `--network none`.
#   * stdout and stderr of the installer are split into `/install.path` and `/install.log`
#     so the page's claim about stdout stays checkable, and so a verdict can be tied by
#     file to the binary this step produced (the report carries no engine version).
#
# **The intercepting proxy, and why the CA is here.** This machine's containers are behind
# an intercepting proxy: `curl` to anything returns `(60) SSL certificate problem:
# self-signed certificate in certificate chain`, and the certificate offered for
# api.github.com is issued by the corporate proxy's own CA rather than by a public one.
# Measured with a control in the same run on the previous campaign — `https://example.com`
# fails identically — so the installer is not what is broken. This is the one place the
# container stops being a faithful stand-in for a GitHub runner.
#
# apt lists are not cleaned (omamori blocks the rm -rf string on the host side).
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps bash git curl

COPY proxy-ca.pem /usr/local/share/ca-certificates/proxy.crt
RUN update-ca-certificates > /tmp/ca.log 2>&1 && tail -1 /tmp/ca.log

# The candidates, each alone so a missing package prints MISSING rather than failing the
# build. `ruby` carries the slate candidate (overcommit, installed below); `recutils` and
# `detox` are real dynamically linked C tools used as additional gate rows — they fail
# selection rule 1 (neither has a GitHub home with 1,000 stars) and never enter the slate,
# but a gate whose greens are all toys has only been shown half of its range.
RUN for p in ruby ruby-dev build-essential recutils detox; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt

# The slate candidate. Pinned: a run that measured whatever the gem server had that hour
# could not be repeated, and the version is what a report would name.
RUN gem install --no-document overcommit -v 0.73.0 > /tmp/gem.log 2>&1 && overcommit --version || (tail -20 /tmp/gem.log; echo "overcommit MISSING")

# lefthook, for the gate's visibility RED leg only — never a candidate here.
#
# **Pinned to 1.13.6, which is the version the previous campaign admitted** — the claim is
# that this gate turns away *that* binary, so any other version would be a different
# measurement. (Upstream is at 2.1.14 today.)
#
# Installed from the release asset rather than through the project's `install.sh`: piping
# that script produced an empty log and no binary here, and the `2>/dev/null … || true`
# around it turned a failed install into a silent one — the build went green with the red
# leg missing. A named asset either arrives or fails the build.
RUN curl -fsSL -o /tmp/lefthook \
      https://github.com/evilmartians/lefthook/releases/download/v1.13.6/lefthook_1.13.6_Linux_aarch64 \
    && install -m 0755 /tmp/lefthook /usr/local/bin/lefthook \
    && lefthook version

# ---- the adoption step under test ---------------------------------------------------------
COPY install-sideeye.sh /opt/install-sideeye.sh
RUN sh /opt/install-sideeye.sh v1.5.0 /opt/se > /install.path 2>/install.log; \
    echo "installer exit: $?"; \
    echo "stdout: [$(cat /install.path)]"; \
    grep -E 'digest|sideeye ' /install.log || true
RUN "$(cat /install.path)" version

WORKDIR /w
