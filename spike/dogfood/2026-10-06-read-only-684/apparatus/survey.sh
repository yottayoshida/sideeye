#!/bin/sh
# Step 4a of the plan, before the engine changes: what each target calls on its state that the
# strace oracle has no name for. The oracle keeps the FIRST such call it meets and refuses there
# (src/oracle.zig), so the wall each earlier campaign recorded says nothing about the calls behind
# it. This runs each operation once under strace alone — no engine — and lists every syscall name
# on a line that mentions the state directory and is in none of the oracle's lists, read from the
# source at /src/oracle.zig (mounted from the commit RESULTS.md names).
#
#   docker run --rm --privileged --network none -v <apparatus>:/ap:ro -v <repo>/src:/src:ro \
#     -v <out>:/out sideeye-ro684 sh /ap/survey.sh
set -u
. /ap/env.sh
mkdir -p /out/survey
python3 - /src/oracle.zig > /out/survey/named.txt <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
names = set()
for block in ("known", "metadata_path_syscalls", "metadata_fd_syscalls", "read_only", "process_syscalls"):
    m = re.search(r"const %s = \[_\][^{]*\{(.*?)\n\};" % block, s, re.S)
    if not m:
        sys.exit("could not find %s in oracle.zig" % block)
    body = "\n".join(l.split("//", 1)[0] for l in m.group(1).split("\n"))
    names.update(re.findall(r'"([a-z0-9_]+)"', body))
print("\n".join(sorted(names)))
EOF
echo "survey: $(wc -l < /out/survey/named.txt) names the oracle classifies (/out/survey/named.txt)"
for t in vim fish dotdrop firewalld; do (
    # A subshell per target: fish's env.sh exports XDG_CONFIG_HOME, which must not reach the rest.
    d=/ap/defines/$t
    sh "$d/seed.sh" > "/out/survey/$t.seed.log" 2>&1 || { echo "$t: seed failed: $(tail -1 "/out/survey/$t.seed.log")"; exit 0; }
    [ -f "$d/env.sh" ] && . "$d/env.sh"
    state=$(sed -n 's/^state *= *"\(.*\)"$/\1/p' "$d/sideeye.toml")
    cwd=$(sed -n 's/^cwd *= *"\(.*\)"$/\1/p' "$d/sideeye.toml")
    # The operation in both of the toml's spellings: an argv array, or a string split on spaces.
    python3 - "$d/sideeye.toml" > "/out/survey/$t.argv" <<'EOF'
import json, re, sys
for line in open(sys.argv[1]):
    m = re.match(r'\s*operation\s*=\s*(.*)$', line)
    if not m: continue
    v = m.group(1).strip()
    argv = json.loads(v) if v.startswith("[") else json.loads(v).split(" ")
    print("\0".join(argv), end="")
EOF
    ( [ -n "$cwd" ] && cd "$cwd"; xargs -0 -a "/out/survey/$t.argv" strace -f -y -qq -e trace=%file,%desc -o "/out/survey/$t.strace" ) > "/out/survey/$t.run.log" 2>&1
    echo "$t: operation exit $? ($(tr '\0' ' ' < "/out/survey/$t.argv"))"
    python3 - "/out/survey/$t.strace" "$state" /out/survey/named.txt <<'EOF' | tee "/out/survey/$t.unnamed.txt"
import re, sys
trace, state, named = sys.argv[1], sys.argv[2].rstrip("/"), set(open(sys.argv[3]).read().split())
seen = {}
for line in open(trace, errors="replace"):
    if state not in line: continue
    m = re.match(r"^\s*(?:\[pid\s+\d+\]\s*|\d+\s+)?([a-z0-9_]+)\(", line)
    if not m: continue
    n = m.group(1)
    if n in named: continue
    seen.setdefault(n, line.strip()[:200])
if not seen:
    print("  no unnamed call on the state directory")
for n, l in sorted(seen.items()):
    print("  %s   e.g. %s" % (n, l))
EOF
); done
