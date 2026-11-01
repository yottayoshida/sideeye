#!/bin/sh
# The operation is a compiled toy, not a script: a shell is a platform binary on macOS and does
# not load the shim.
#
#   SIDEEYE=zig-out/bin/sideeye SHIM=zig-out/lib/libsideeye_shim.{so,dylib} sh spike/check-controls.sh
#   CONTROLS_JSON_OUT=<path> also copies the ten-control preflight document there.
set -u
SIDEEYE=${SIDEEYE:-zig-out/bin/sideeye}
case "$(uname -s)" in Darwin) SHIM=${SHIM:-zig-out/lib/libsideeye_shim.dylib} ;; *) SHIM=${SHIM:-zig-out/lib/libsideeye_shim.so} ;; esac
SIDEEYE=$(cd "$(dirname "$SIDEEYE")" && pwd)/$(basename "$SIDEEYE")
SHIM=$(cd "$(dirname "$SHIM")" && pwd)/$(basename "$SHIM")
d=$(mktemp -d "${TMPDIR:-/tmp}/check-controls.XXXXXX")
fails=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

cat > "$d/op.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    const char *s = getenv("SIDEEYE_STATE_DIR");
    char p[4096];
    for (int i = 1; i <= 8; i++) {
        snprintf(p, sizeof p, "%s/l%d", s, i);
        int fd = open(p, O_WRONLY | O_TRUNC);
        if (fd < 0 || write(fd, "ok\n", 3) != 3 || close(fd) != 0) return 1;
    }
    if (argc > 1) {
        snprintf(p, sizeof p, "%s/%s", s, argv[1]);
        int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0 || write(fd, "x\n", 2) != 2 || close(fd) != 0) return 1;
    }
    return 0;
}
EOF
cc -O0 -o "$d/op" "$d/op.c" || { echo "BROKEN could not build the operation"; exit 2; }

cat > "$d/check.sh" <<'EOF'
#!/bin/sh
s=${SIDEEYE_STATE_DIR:?}
legs=${SIDEEYE_LEGS:-/dev/null}
[ -f "$s/NO_LEGS" ] && exit 1
[ -f "$s/MALFORMED" ] && { echo "l1 maybe" >> "$legs"; exit 1; }
[ -f "$s/DIR_LEGS" ] && { mkdir "$legs"; exit 1; }
rc=0
for i in 1 2 3 4 5 6 7 8; do
    if [ "$(cat "$s/l$i" 2>/dev/null)" = ok ]; then
        [ -f "$s/STOP_EARLY" ] || echo "l$i ok" >> "$legs"
    else
        echo "l$i fail" >> "$legs"; rc=1
        [ -f "$s/STOP_EARLY" ] && exit 1
    fi
done
[ -f "$s/LIE_EXIT" ] && rc=$((1 - rc))
exit $rc
EOF
brk() {  # brk <name> <files to break...> [-- <markers>]
    n=$1; shift
    { echo '#!/bin/sh'; echo 's=${SIDEEYE_STATE_DIR:?}'
      for f in "$@"; do case $f in l*) echo "echo broken > \"\$s/$f\"" ;; *) echo ": > \"\$s/$f\"" ;; esac; done; } > "$d/$n.sh"
}
brk only l1
brk more l2 l3
brk other l4
brk nothing
brk lie l5 LIE_EXIT
brk silent l6 NO_LEGS
brk junk l7 MALFORMED
brk early l8 STOP_EARLY
brk dirlegs l1 DIR_LEGS
printf '#!/bin/sh\nexit 1\n' > "$d/refuses.sh"
chmod 755 "$d"/*.sh

printf '#!/bin/sh\nfor i in 1 2 3 4 5 6 7 8; do echo ok > "$SIDEEYE_STATE_DIR/l$i"; done\n' > "$d/seed.sh"
chmod 755 "$d/seed.sh"
# op-red leaves l1 failing, so the checker is red on the state the recording left.
sed 's|write(fd, "ok\\n", 3) != 3|write(fd, i == 1 ? "no\\n" : "ok\\n", 3) != 3|' "$d/op.c" > "$d/op-red.c"
cc -O0 -o "$d/op-red" "$d/op-red.c" || { echo "BROKEN could not build the red operation"; exit 2; }

define() {  # define <toml> <operation>
    cat > "$d/$1" <<EOF
[world]
state = "state"

[define]
setup     = "./seed.sh"
operation = "$2"
check     = "./check.sh"

[controls]
l0 = "./refuses.sh"
l1 = "./only.sh"
l2 = "./more.sh"
l3 = "./other.sh"
l4 = "./nothing.sh"
l5 = "./lie.sh"
l6 = "./silent.sh"
l7 = "./junk.sh"
l9 = "./only.sh"
ld = "./dirlegs.sh"
l8 = "./early.sh"
EOF
}
define good.toml "$d/op"
define red.toml "$d/op-red"
# Writes LIE_EXIT into the state, so the checker exits 1 over legs that are all ok.
define lie.toml "$d/op LIE_EXIT"

words() {  # words <toml> <label> [flags...] -> prints "baseline=<w> l1=<w> ..."
    t=$1; w=$2; shift 2
    mkdir -p "$d/state"
    "$SIDEEYE" preflight --config "$d/$t" --shim "$SHIM" --work "$d/work-$w" --json "$d/$w.json" "$@" > "$d/$w.txt" 2>&1
    echo "exit=$?" >> "$d/$w.txt"
    python3 - "$d/$w.json" <<'PY'
import json, sys
try:
    c = json.load(open(sys.argv[1]))["controls"]
except Exception as e:
    print("no-controls(%s)" % type(e).__name__); sys.exit()
print(" ".join(["baseline=" + c["baseline"]["word"]] + ["%s=%s" % (k["leg"], k["word"]) for k in c["legs"]]))
PY
}

recorded() {  # recorded <l1 content> -> 0 when the state is what the recording left
    [ "$(cat "$d/state/l1")" = "$1" ] || return 1
    for i in 2 3 4 5 6 7 8; do [ "$(cat "$d/state/l$i")" = ok ] || return 1; done
    for m in STOP_EARLY NO_LEGS MALFORMED DIR_LEGS; do [ ! -e "$d/state/$m" ] || return 1; done
}

want="baseline=none l0=control_failed l1=only_its_leg l2=more_than_its_leg l3=not_its_leg l4=none l5=exit_disagrees l6=legs_not_reported l7=legs_malformed l9=its_leg_not_reported ld=legs_malformed l8=legs_incomplete"
got=$(words good.toml good)
[ "$got" = "$want" ] && echo "ok   each control is reported by its own word" || { fail "the controls: got $got"; sed 's/^/     | /' "$d/good.txt" | head -30; }
# l8, the last control, breaks l8 and leaves STOP_EARLY: only the final restore puts them back.
recorded ok && echo "ok   the state is put back to what the recording left" || fail "the state was left as a control broke it"

got=$(words good.toml twice --twice)
[ "$got" = "$want" ] && echo "ok   under --twice, two runs that agree are followed by the same controls" || fail "--twice: got $got"

for t in red lie; do
    got=$(words $t.toml $t)
    case "$got" in
    baseline=legs_red*|baseline=exit_disagrees*)
        rest=$(printf '%s\n' "$got" | tr ' ' '\n' | sed 1d | grep -vc '=baseline_red$')
        [ "$rest" = 0 ] && echo "ok   a baseline the checker fails ($(printf '%s' "$got" | cut -d' ' -f1)) turns every control into baseline_red" \
            || fail "$t: a control kept its own word under a red baseline: $got" ;;
    *) fail "$t: the baseline was not red: $got"; sed 's/^/     | /' "$d/$t.txt" | head -20 ;;
    esac
    if [ "$t" = red ]; then recorded no && echo "ok   a red baseline leaves the state the recording left" || fail "a red baseline left another state"; fi
done

# For the report-schema check, which needs a preflight document that carries `controls`.
[ -n "${CONTROLS_JSON_OUT:-}" ] && cp "$d/good.json" "$CONTROLS_JSON_OUT"
[ "$fails" = 0 ] && echo "all checks passed ($d)" || { echo "$fails failed ($d)"; exit 1; }
