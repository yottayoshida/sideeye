#!/bin/sh
# #796's measurements on a macOS host whose sudo needs no password (a hosted runner).
#   M1  where the shipped reader refuses: a toy that prints, a toy that moves a state file onto
#       fd 1 the way GNU dd does, its control moving an outside file there, and gdd itself;
#       then the same four with `-f filesys` dropped from the fs_usage launch.
#   M2  whether an unfiltered capture prints `dup2` with both numbers, and whether a child's
#       lines before its exec carry the thread id its lines after the exec carry.
#   M3  line counts with and without the filter over the same window, and fs_usage's own
#       `buffer overrun` notices, which go to its stderr.
# Everything lands in $OUT; the summary is $OUT/summary.txt.
set -u

HERE="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=${OUT:-$HOME/m796-out}
WORK="$(mktemp -d "$HOME/m796-XXXXXX")"
mkdir -p "$OUT"
SUM="$OUT/summary.txt"
say() { echo "$*" | tee -a "$SUM"; }

sudo -v || { say "sudo unavailable; nothing was measured"; exit 1; }
( cd "$HERE" && zig build --prefix "$WORK/cur" ) || { say "zig build failed"; exit 1; }
mkdir -p "$WORK/variant-src"
git -C "$HERE" archive HEAD | tar -x -C "$WORK/variant-src"
sed -i '' 's/"-t", limit, "-f", "filesys" }/"-t", limit }/' "$WORK/variant-src/src/main.zig"
grep -q '"-t", limit }' "$WORK/variant-src/src/main.zig" || { say "the filter could not be dropped from the variant's launch line"; exit 1; }
( cd "$WORK/variant-src" && zig build --prefix "$WORK/nofilter" ) || { say "variant build failed"; exit 1; }

cat > "$WORK/print_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    char p[1024]; snprintf(p, sizeof p, "%s/keep", argv[1]);
    int fd = open(p, O_WRONLY); if (fd < 0) return 1;
    if (write(fd, "ok\n", 3) != 3) return 1;
    close(fd);
    printf("done\n"); fflush(stdout);
    fprintf(stderr, "note\n");
    return 0;
}
EOF
cat > "$WORK/dup2_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    char p[1024]; snprintf(p, sizeof p, "%s/keep", argv[1]);
    int fd = open(p, O_WRONLY); if (fd < 0) return 1;
    if (dup2(fd, 1) != 1) return 1;
    close(fd);
    if (write(1, "ok\n", 3) != 3) return 1;
    if (write(2, "3 bytes copied\n", 15) != 15) return 1;
    return 0;
}
EOF
cat > "$WORK/dup2_out_toy.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    int lf = open(argv[2], O_WRONLY | O_CREAT | O_APPEND, 0644); if (lf < 0) return 1;
    if (dup2(lf, 1) != 1) return 1;
    close(lf);
    if (write(1, "log\n", 4) != 4) return 1;
    char p[1024]; snprintf(p, sizeof p, "%s/keep", argv[1]);
    int fd = open(p, O_WRONLY); if (fd < 0) return 1;
    if (write(fd, "ok\n", 3) != 3) return 1;
    close(fd);
    return 0;
}
EOF
cat > "$WORK/launcher.c" <<'EOF'
#include <fcntl.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>
int main(int argc, char **argv) {
    pid_t c = fork();
    if (c == 0) {
        int fd = open(argv[1], O_WRONLY | O_CREAT | O_APPEND, 0644);
        dup2(fd, 1); close(fd);
        execv(argv[2], argv + 2);
        _exit(127);
    }
    int st; waitpid(c, &st, 0);
    return 0;
}
EOF
for t in print_toy dup2_toy dup2_out_toy launcher; do
    /usr/bin/cc -O1 -o "$WORK/$t" "$WORK/$t.c" || { say "cc $t failed"; exit 1; }
done

ensure_no_fs_usage() {
    pgrep -x fs_usage >/dev/null 2>&1 || return 0
    sudo -n /usr/bin/pkill -INT -x fs_usage 2>/dev/null; sleep 2
    sudo -n /usr/bin/pkill -KILL -x fs_usage 2>/dev/null; sleep 1
}

field() { python3 -c "
import json,sys
try:
    r=json.load(open(sys.argv[1])); print(r.get('verdict'), r.get('unknown_reason') or '-', 'oracle_verified=%s' % r.get('oracle_verified'), '|', (r.get('message') or '')[:300])
except Exception as e: print('(no json)', e)" "$1"; }

GDD=$(command -v gdd || true)
leg() {  # leg <binary-dir> <tag> <name> <operation...>
    bin=$1; tag=$2; name=$3; shift 3
    ensure_no_fs_usage
    st="$WORK/st-$tag-$name"; mkdir -p "$st"; printf 'old\n' > "$st/keep"; printf 'old-contents\n' > "$st/a.txt"
    op=$(printf '%s' "$*" | sed "s#@ST@#$st#g; s#@W@#$WORK#g")
    "$bin/bin/sideeye" explore --state "$st" --operation "$op" --shim "$bin/lib/libsideeye_shim.dylib" \
        --work "$WORK/w-$tag-$name" --json "$OUT/$tag-$name.json" --oracle-fs-usage > "$OUT/$tag-$name.txt" 2>&1
    say "  $tag $name exit=$? $(field "$OUT/$tag-$name.json")"
}
say "== M1: the shipped launch (-f filesys), then the launch without the filter"
printf 'new\n' > "$WORK/new"
for b in cur nofilter; do
    leg "$WORK/$b" "$b" print "$WORK/print_toy @ST@"
    leg "$WORK/$b" "$b" dup2 "$WORK/dup2_toy @ST@"
    leg "$WORK/$b" "$b" dup2-outside "$WORK/dup2_out_toy @ST@ @W@/outside.log"
    if [ -n "$GDD" ]; then leg "$WORK/$b" "$b" gdd "$GDD if=$WORK/new of=@ST@/a.txt"; else say "  $b gdd NOT MEASURED: gdd is not installed"; fi
done

capture() {  # capture <tag> <fs_usage args...>
    tag=$1; shift
    ensure_no_fs_usage
    sudo -n /usr/bin/fs_usage -w -e -t 6 "$@" > "$OUT/raw-$tag.txt" 2> "$OUT/raw-$tag.err" &
    sleep 2
    mkdir -p "$WORK/st-raw"; printf 'old\n' > "$WORK/st-raw/keep"
    "$WORK/launcher" "$WORK/launcher-$tag.out" "$WORK/dup2_toy" "$WORK/st-raw"
    sleep 5
    ensure_no_fs_usage
    say "  $tag: $(wc -l < "$OUT/raw-$tag.txt" | tr -d ' ') lines in about 6 s; overrun notices: $(grep -c 'buffer overrun' "$OUT/raw-$tag.err")"
    say "  $tag: dup2/dup lines from the launcher or the toy:"
    grep -E '^[0-9:.]+ +dup2? ' "$OUT/raw-$tag.txt" | grep -E 'launcher|dup2_toy' | head -5 | sed 's/^/      /' | tee -a "$SUM" >/dev/null
    say "  $tag: lines of the launcher's child and the toy (command.thread), first 12:"
    grep -E '(launcher|dup2_toy)\.[0-9]+ *$' "$OUT/raw-$tag.txt" | head -12 | sed 's/^/      /' | tee -a "$SUM" >/dev/null
}
say "== M2/M3: one fork+dup2+exec under each launch"
capture nofilter
capture filesys -f filesys
say "== M3: call names that appear only without the filter (top 25 by count)"
awk '{print $2}' "$OUT/raw-nofilter.txt" | sort | uniq -c | sort -rn > "$OUT/calls-nofilter.txt"
awk '{print $2}' "$OUT/raw-filesys.txt" | sort | uniq -c | sort -rn > "$OUT/calls-filesys.txt"
awk 'NR==FNR {seen[$2]=1; next} !($2 in seen)' "$OUT/calls-filesys.txt" "$OUT/calls-nofilter.txt" | head -25 | sed 's/^/      /' | tee -a "$SUM" >/dev/null
say "done; work directory $WORK"
