#!/bin/sh
# Reproduce #638's acceptance case: the judged set of `lmdb-utils`' FINAL define, named.
#
# `runs/lmdb-utils/revisions/02.toml` is the state the subject ended on at 07:49:50 — it
# declares `data.mdb` scratch, and the engine then said `1 path(s) judged pre-or-post` with
# nothing naming the one. That path is `lock.mdb`; it never violated, so no FAIL ever named
# it, and it was the whole defect (RESULTS.md condition 5, ADR 0078).
#
# The case is rebuilt by `lmdb-case-from-transcript.sh`, which this pipes into the box —
# read that file for what is quoted from where. Not part of CI and not a campaign phase: it
# wants Docker, the network for one apt install, and an engine cross-built for the box.
#
#   zig build -Dtarget=aarch64-linux-gnu      # or x86_64-linux-gnu, matching your machine
#   sh spike/authoring-cost/reproduce-lmdb-judged-set.sh
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
img=sideeye-lmdb-638-repro

[ -x "$root/zig-out/bin/sideeye" ] || {
    echo "no engine at zig-out/bin/sideeye — build it for the box first" >&2
    exit 2
}
case "$(file -b "$root/zig-out/bin/sideeye" 2>/dev/null)" in
    *ELF*) ;;
    *) echo "zig-out/bin/sideeye is not an ELF binary; cross-build it (-Dtarget=...-linux-gnu)" >&2; exit 2 ;;
esac

# bookworm, as the study's box was (see Dockerfile beside this script). The target version is
# printed by the inner script rather than pinned here: meta.json records what the run
# measured (0.9.24-1), and a mismatch is something to see rather than to silently satisfy.
docker build -q -t "$img" - >/dev/null <<'DOCKEREOF'
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends lmdb-utils strace ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -m user
ENV USER=user HOME=/home/user
DOCKEREOF

# SYS_PTRACE and an unconfined seccomp profile because the run carries an strace oracle;
# the study's box was entered with `docker exec`, so this is the same privilege by another
# route. `--user user` for the reason the study's Dockerfile gives: a container without a
# USER hands targets apparatus friction instead of their own behaviour.
exec docker run --rm -i \
    --cap-add SYS_PTRACE --security-opt seccomp=unconfined \
    -v "$root/zig-out:/engine:ro" \
    -v "$here/runs/lmdb-utils/revisions:/revisions:ro" \
    --user user "$img" sh -s < "$here/lmdb-case-from-transcript.sh"
