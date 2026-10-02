#!/bin/sh
# One upstream fix, one source tree mounted on /src (base or fix): the 2026-09-16 define explored
# with the installed v1.7.0, a FAIL replayed twice, then what a rename-based write can change —
# modes, a relative symlink, a second hard link, `ulimit -f 0`, and what a kill just before the
# rename leaves. Every probe command is echoed.
#
#   sh measure.sh codespell|rubocop          (inside the box; /src is the tool's checkout)
set -u
t=${1:?usage: measure.sh codespell|rubocop}
SE=$(cat /install.path); SD=/s/fix/$t; export SD
case "$t" in
    codespell) tool="python3 -m codespell_lib -w"; ext=txt; ver() { python3 -m codespell_lib --version; } ;;
    rubocop)   tool="ruby /src/exe/rubocop -a --force-default-config --only Layout/SpaceInsideParens"; ext=rb; ver() { ruby /src/exe/rubocop --version; } ;;
    *) echo "unknown target $t"; exit 2 ;;
esac
case "$t" in codespell) op="$tool $SD/a.txt $SD/b.txt $SD/c.txt" ;; rubocop) op="$tool $SD/a.rb $SD/b.rb" ;; esac
reason() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$1" 2>/dev/null || echo "none -"; }
run() { echo "\$ $*"; sh -c "$*" 2>&1; }
bad() { case "$t" in codespell) printf 'MARKER keep\nThe reciever did not seperate.\n' > "$1" ;; rubocop) printf '# MARKER\nputs( "x" )\n' > "$1" ;; esac; }

echo "## versions"; echo "tool: $(ver 2>&1 | tail -1)"; "$SE" version
echo; echo "## explore"
rm -rf /s/fix && mkdir -p /s/fix   # the engine makes the leaf of --state, not its parent
"$SE" explore --state "$SD" --setup "/ap/fix/setup-$t.sh" --operation "$op" --check "/ap/fix/check-$t.sh" \
    --oracle /usr/bin/strace --work /out/work --json /out/explore.json > /out/explore.txt 2>&1
rc=$?; echo "explore exit $rc: $(reason /out/explore.json)"
if [ "$rc" = 1 ]; then
    case_json=$(ls /out/work/cases/*.json 2>/dev/null | head -1)
    for i in 1 2; do
        "$SE" replay "$case_json" --oracle /usr/bin/strace --work "/out/replay$i" --json "/out/replay$i.json" > "/out/replay$i.txt" 2>&1
        echo "replay $i exit $?: $(reason "/out/replay$i.json")"
    done
fi

echo; echo "## modes"
rm -rf /p && mkdir -p /p/m && cd /p/m
for m in 600 664 755; do bad "f$m.$ext"; chmod $m "f$m.$ext"; done
run "stat -c '%a %n' *.$ext"
run "$tool f600.$ext f664.$ext f755.$ext > /dev/null; echo \"exit \$?\""
run "stat -c '%a %n' *.$ext"

echo; echo "## relative symlink, run from the parent"
rm -rf /p/l && mkdir -p /p/l/shared /p/l/mod && bad "/p/l/shared/x.$ext" && ln -s "../shared/x.$ext" "/p/l/mod/x.$ext" && cd /p/l
run "$tool mod/x.$ext > /dev/null; echo \"exit \$?\""
run "ls -l mod; cat shared/x.$ext; ls -A shared mod"

echo; echo "## a second hard link"
rm -rf /p/h && mkdir -p /p/h && cd /p/h && bad "one.$ext" && ln "one.$ext" "two.$ext"
run "stat -c '%h links, inode %i  %n' one.$ext two.$ext"
run "$tool one.$ext > /dev/null; echo \"exit \$?\""
run "stat -c '%h links, inode %i  %n' one.$ext two.$ext; cmp one.$ext two.$ext && echo 'same bytes' || echo 'the two names now differ'"

echo; echo "## ulimit -f 0"
rm -rf /p/u && mkdir -p /p/u && cd /p/u && bad "x.$ext"
run "wc -c < x.$ext"
run "( ulimit -f 0; $tool x.$ext > /dev/null 2>&1 ); echo \"exit \$?\""
run "wc -c < x.$ext; ls -A"

echo; echo "## SIGKILL on entry to rename (strace), then the directory"
rm -rf /p/k && mkdir -p /p/k && cd /p/k && bad "x.$ext"
run "strace -f -o /dev/null -e trace=rename,renameat,renameat2 -e inject=rename,renameat,renameat2:signal=KILL $tool x.$ext > /dev/null 2>&1; echo \"exit \$?\""
run "ls -lA; wc -c x.$ext"
exit 0
