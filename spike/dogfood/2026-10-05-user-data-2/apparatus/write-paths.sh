#!/bin/sh
# How each target wrote its state: the operation once under strace from its seed, keeping only the
# calls on the state root — the opens, renames, unlinks and truncates that name a path inside it, and
# the writes, syncs and truncates on a descriptor such an open returned. For RESULTS.md and the
# target-classes rows, which say why a PASS passed and what a FAIL's report quotes.
#
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1005 sh /ap/write-paths.sh <name> [...]
#
# Copied from 2026-10-03's, whose filter dropped every path under /s/aux (a state root here for
# regctl, velero, wrangler and others) and kept Go's SIGURG lines; this one follows the state root.
set -u
. /ap/env.sh
for t in "$@"; do
    ( d=/ap/defines/$t
      [ -f "$d/env.sh" ] && . "$d/env.sh"
      state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      sh "$d/seed.sh" > /dev/null 2>&1
      cd "$cwd" && strace -f -qq -e signal=none -e trace=openat,creat,write,pwrite64,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync \
          -o /tmp/st.$t $op < /dev/null > /dev/null 2>&1
      echo "=== $t ($op)"
      python3 - "$state" "$cwd" /tmp/st.$t <<'P'
import re, sys
state, cwd, path = sys.argv[1], sys.argv[2], sys.argv[3]
inside = lambda p: (p if p.startswith("/") else cwd.rstrip("/") + "/" + p).startswith(state.rstrip("/") + "/")
fds = {}
out = []
for line in open(path, errors="replace"):
    line = re.sub(r"^\d+ +", "", line.rstrip("\n"))
    pid_fd = None
    m = re.match(r'openat\(AT_FDCWD, "([^"]*)", ([^,)]*).*\) = (\d+)', line)
    if m:
        if "O_RDONLY" not in m.group(2) and inside(m.group(1)):
            fds[m.group(3)] = m.group(1); out.append(line)
        else:
            fds.pop(m.group(3), None)
        continue
    m = re.match(r'(write|pwrite64|fsync|fdatasync|ftruncate)\((\d+)', line)
    if m:
        if m.group(2) in fds: out.append(line)
        continue
    if any(inside(p) for p in re.findall(r'"([^"]*)"', line)):
        out.append(line)
for l in out[:24]: print(l[:150])
if len(out) > 24: print(f"... {len(out) - 24} more")
P
    )
done
