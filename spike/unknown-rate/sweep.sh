#!/bin/sh
# The #84 sweep: runs every corpus.tsv trial fresh, one container per
# invocation, and writes the manifest the published tables are recomputed
# from. Host-side (drives docker); the launchers under launchers/ run
# inside. This is an OPEN measurement — no seals, no blindness claims; what
# it borrows from the campaign discipline is only the honesty machinery:
# fresh roots, refuse-don't-overwrite, apparatus identity recorded per
# trial, raw exit codes read before any pipe.
#
# Usage: sweep.sh <generation-id>     (see generations.tsv)
#
# The generation decides three things: which artifacts directory this sweep
# writes, which groups it covers, and which corpus rows it expects. #239
# re-measures A alone while B's 2026-08-16 numbers stand, so "one sweep, one
# engine build" now holds per generation rather than across the page — and
# the id is a required argument because a sweep that picks its own scope
# could quietly cover less than the generation it publishes under.
#
# Manifest columns (tab-separated, <artifacts_dir>/manifest.tsv):
#   trial_id group tool class judge image_id launcher_argv define_digest
#   report_path launcher_rc report_sha256
# define_digest = sha256 over the sorted "sha256  path" lines of every file
# the corpus row's `defines` column names, computed from the CLEAN worktree
# this sweep ran (count.py recomputes it from the checkout and must agree).
# report_sha256 = sha256 of the report this trial produced, so the file at
# report_path is bound to the sweep that wrote it and not merely to a name
# (#349). A funnel wall runs no engine and carries `-`.
set -u

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)

gen=${1:-}
[ -n "$gen" ] || { echo "sweep: usage: sweep.sh <generation-id>   (see generations.tsv)" >&2; exit 2; }

genrow=$(awk -F'\t' -v g="$gen" '!/^#/ && $1 == g {print; exit}' "$here/generations.tsv")
[ -n "$genrow" ] || { echo "sweep: no generation '$gen' in generations.tsv" >&2; exit 2; }
gen_dir=$(printf '%s\n' "$genrow" | cut -f3)
gen_groups=$(printf '%s\n' "$genrow" | cut -f4)
gen_status=$(printf '%s\n' "$genrow" | cut -f5)

# A completed generation is a published measurement; re-running one in place
# would replace numbers whose date is already in print. Re-measuring means a
# new generation row and a new directory, which is also what keeps the old
# figures available to publish beside the new ones.
[ "$gen_status" = "unstarted" ] || {
    echo "sweep: generation $gen is '$gen_status', not 'unstarted' — completed generations are never re-measured in place" >&2
    exit 2
}

ARTS=$here/$gen_dir

if [ -e "$ARTS" ]; then
    echo "sweep: $ARTS already exists — a sweep never overwrites its predecessor" >&2
    exit 2
fi

# The defines are hashed from this worktree; an unclean tree would make
# "verbatim" unprovable. artifacts/ itself is created below, after this check.
if [ -n "$(cd "$ROOT" && git status --porcelain)" ]; then
    echo "sweep: worktree not clean — the define digests would not match any commit" >&2
    exit 2
fi

echo "sweep: building the Linux engine + shim"
(cd "$ROOT" && zig build -Dtarget=aarch64-linux-gnu) || exit 2

echo "sweep: building the images"
docker build -q -t sideeye-ur-campaign -f "$ROOT/spike/Dockerfile" "$ROOT/spike" || exit 2
docker build -q -t sideeye-ur-assisted -f "$ROOT/spike/assisted/Dockerfile" "$ROOT/spike/assisted" || exit 2
docker build -q -t sideeye-ur-extra -f "$here/Dockerfile" "$here" || exit 2
# The cohort images each COPY a tarball or vendored tree out of their own
# artifacts/ directory, which is gitignored. Each cohort ships the fetcher
# for its own inputs — run spike/cohort<N>/fetch-artifacts.sh on the HOST
# first (host-side on purpose: the sha256 pins live in that script and in
# the Dockerfile, and the downloads stay out of the image). A fresh checkout
# has none of them, so these builds fail until the fetch has run; that
# failure is loud here rather than a missing trial later.
#
# Only the cohorts THIS generation reaches are built. Building all three
# unconditionally would make a B-only generation — which this page promises
# is possible — depend on artifacts no trial in it uses.
needed=$(awk -F'\t' -v g="$gen" -v groups=",$gen_groups," '
    FNR == NR { if ($0 !~ /^#/ && NF >= 5) { gidx[$1] = ++n; if ($1 == g) target = n } ; next }
    /^#/ { next }
    NF != 12 { next }
    $6 != "cohort.sh" { next }
    { if (index(groups, "," $2 ",") && ($11 in gidx) && gidx[$11] <= target) { split($7, a, " "); print a[1] } }
' "$here/generations.tsv" "$here/corpus.tsv" | sort -u)
for c in $needed; do
    case "$c" in cohort2|cohort3|cohort4) ;; *) echo "sweep: unknown cohort '$c' in corpus args" >&2; exit 2 ;; esac
    docker build -q -t "sideeye-ur-$c" -f "$ROOT/spike/$c/Dockerfile" "$ROOT/spike/$c" || {
        echo "sweep: $c image build failed — run spike/$c/fetch-artifacts.sh on the host first" >&2
        exit 2
    }
done

# This mkdir is load-bearing for the ro mounts below: the artifacts dir is
# the nested rw mountpoint inside the read-only /work bind, and docker
# cannot create a missing mountpoint on a read-only rootfs (measured — the
# smoke without this dir failed with EROFS at container create).
mkdir -p "$ARTS"

# Apparatus identity, recorded from inside a container (the binary is a
# Linux cross-build; the host cannot even run it).
docker run --rm -v "$ROOT":/work:ro sideeye-ur-extra sh -c '
  /work/zig-out/bin/sideeye 2>&1 | head -1
  sha256sum /work/zig-out/bin/sideeye /work/zig-out/lib/libsideeye_shim.so
' > "$ARTS/apparatus.txt" 2>&1 || { echo "sweep: engine identity capture failed" >&2; exit 2; }
grep -q "^sideeye " "$ARTS/apparatus.txt" || {
    echo "sweep: the engine did not print its banner — wrong-platform build?" >&2; exit 2; }
{ echo "head: $(cd "$ROOT" && git rev-parse HEAD)"
  docker images --no-trunc --format '{{.Repository}} {{.ID}}' \
      | grep -E '^sideeye-ur-' ; } >> "$ARTS/apparatus.txt"

image_for() {
    case "$1" in
      campaign.sh) echo sideeye-ur-campaign ;;
      assisted.sh) echo sideeye-ur-assisted ;;
      watson.sh|dogfood.sh|bgroup.sh) echo sideeye-ur-extra ;;
      # cohort.sh is the one launcher whose image depends on its arguments:
      # its first argument names the cohort, and each cohort pins its own
      # distribution of its own targets. Passing the args in keeps that
      # mapping here rather than spreading it into the loop.
      cohort.sh)
          case "${2:-}" in
            cohort2*) echo sideeye-ur-cohort2 ;;
            cohort3*) echo sideeye-ur-cohort3 ;;
            cohort4*) echo sideeye-ur-cohort4 ;;
            *) return 1 ;;
          esac ;;
      *) return 1 ;;
    esac
}

digest_for() {
    # $1 = ;-separated repo-relative paths (file or directory). A path that
    # does not exist is an apparatus error, never an empty digest — an empty
    # hash would read as "hashed and clean". The caller must capture with
    # `d=$(digest_for …) || exit 2`: a bare command substitution inside
    # printf would swallow the failure (R1 measured the sweep finishing
    # rc=0 over an empty digest column).
    out=$(cd "$ROOT" && for p in $(printf '%s' "$1" | tr ';' ' '); do
        [ -e "$p" ] || { echo "MISSING:$p"; exit 9; }
        if [ -d "$p" ]; then find "$p" -type f -exec sha256sum {} +
        else sha256sum "$p"; fi
    done)
    case "$out" in ""|MISSING:*|*"MISSING:"*)
        echo "sweep: define path missing while hashing: $1" >&2; return 1 ;;
    esac
    printf '%s\n' "$out" | sort | sha256sum | cut -d' ' -f1
}

manifest=$ARTS/manifest.tsv
: > "$manifest"
ran=""   # invocation dedup: dogfood runs once, registers two trials

# No pipeline around this loop: a `grep | while` subshell would swallow both
# the dedup state and any `exit` (measured class in this workspace — pipes
# hide failures).
# The generation's expected trial set: every corpus row in a group this
# generation covers whose `since` is this generation or an earlier one.
# Generations.tsv's row order IS the generation order — the index comparison
# below reads it that way, so a generation inserted out of order would
# change which rows are expected rather than fail quietly.
corpus_stripped=$ARTS/corpus-stripped.tsv
awk -F'\t' -v g="$gen" -v groups=",$gen_groups," '
    FNR == NR {
        if ($0 !~ /^#/ && NF >= 5) { gidx[$1] = ++n; if ($1 == g) target = n }
        next
    }
    /^#/ { next }
    NF != 12 { next }
    {
        if (!($11 in gidx)) {
            printf "sweep: corpus row %s has since=%s, which is not a generation\n", $1, $11 > "/dev/stderr"
            bad = 1
            next
        }
        if (index(groups, "," $2 ",") && gidx[$11] <= target) print
    }
    END { if (bad) exit 3 }
' "$here/generations.tsv" "$here/corpus.tsv" > "$corpus_stripped" || exit 2

[ -s "$corpus_stripped" ] || {
    echo "sweep: generation $gen expects no trials — groups '$gen_groups' match nothing in corpus.tsv" >&2
    exit 2
}
expected_rows=$(wc -l < "$corpus_stripped" | tr -d ' ')
echo "sweep: generation $gen covers $gen_groups — $expected_rows trials"

while IFS="$(printf '\t')" read -r id group tool class judge launcher args artdir rpath defines since flags; do
    [ -n "$id" ] || continue
    if [ "$launcher" = "-" ]; then
        # Funnel wall: no engine run; the row still reaches the manifest so
        # the funnel table's denominator is asserted, not implied.
        d=$(digest_for "$defines") || exit 2
        printf '%s\t%s\t%s\t%s\t%s\t-\twall:%s\t%s\t-\t-\t-\n' \
            "$id" "$group" "$tool" "$class" "$judge" "$args" "$d" >> "$manifest"
        continue
    fi
    img=$(image_for "$launcher" "$args") || { echo "sweep: no image for '$launcher $args'" >&2; exit 2; }
    imgid=$(docker images --no-trunc --format '{{.ID}}' "$img" | head -1)
    [ -n "$imgid" ] || { echo "sweep: no image id for $img — build failed upstream?" >&2; exit 2; }
    inv="$launcher $args"
    case " $ran " in *" $inv "*) already=1 ;; *) already=0 ;; esac
    if [ "$already" = 0 ]; then
        ran="$ran $inv"
        echo "sweep: $id — $launcher $args"
        # The repo mounts read-only: the trials drive real Debian packages
        # under crash injection as root, and nothing they do may write into
        # the checkout. Only the artifacts tree is writable (R1 measured a
        # launcher-arg bug creating a directory in the repo root — the ro
        # mount turns that whole class into a loud failure).
        docker run --rm -v "$ROOT":/work:ro \
            -v "$ARTS":/work/spike/unknown-rate/artifacts \
            "$img" \
            /work/spike/unknown-rate/launchers/"$launcher" $args \
            /work/spike/unknown-rate/artifacts/"$artdir"
        lrc=$?
        echo "$lrc" > "$ARTS/$artdir/launcher-rc"
        # The oracle log is strace output, so its paths are what the tool actually saw —
        # which on this apparatus means the sweep machine's layout, operator's home
        # included, committed to a public repository and growing by one sweep each time
        # (#350). Fold the prefix here, after the container has exited: the engine writes
        # `work/oracle.txt` and reads it back inside the same run, so touching it earlier
        # would change what that run compares against.
        #
        # Anchored on the SUFFIX, not on $ROOT. What is recorded is not the host path this
        # script knows: Docker Desktop prefixes it (`/run/host_virtiofs/...`), and the
        # checkout name differs between generations. Measured: folding $ROOT leaves every
        # one of the 65 layout-carrying lines in a committed log untouched.
        #
        # `/work` is the one prefix held back, and holding it back is the point rather
        # than an optimisation. It is the read-only mount this script passes to
        # `docker run`, identical on every machine, so it is not layout — and a line
        # often carries BOTH spellings: the string the target passed (`/work/spike/...`)
        # and the host path the kernel resolved it to, in strace's `<...>` fd
        # annotation. Folding both collapses them into one string and the line stops
        # showing that a mount was crossed. Measured on committed logs, lines carrying
        # the `/work` spelling: 96 in the timew leg, 177 in todoman; of those, 47 and 48
        # carry both spellings at once.
        #
        # Held back by rewriting it out of the way and back, rather than by narrowing
        # what the fold accepts. An earlier draft narrowed instead — home directories
        # only — and a checkout under `/root`, `/srv`, `/var/lib/jenkins` or `/opt` then
        # passed through untouched, silently, because the fold had stopped looking and
        # the check below was looking for `/Users` alone.
        #
        # Two passes, because one does not reach them all. strace truncates a string
        # argument at 32 bytes and marks it `"..."`, so `readlinkat` results come out as
        # `"/run/host_virtiofs/Users/i.yoshi"...` — the artifacts directory the first
        # pattern anchors on is not in the line at all. The second takes what is left
        # under Docker Desktop's mount prefix; it is blunt because a truncated fragment
        # has no structure to match on. **It can shorten a whole path too** — a complete
        # `/run/host_virtiofs/...` that never reaches the artifacts directory becomes
        # `<repo-truncated>`, naming it worse than it is. Accepted here because every
        # such path on this apparatus IS the host layout; a third pass over bare
        # `/Users/` was written and removed for the same shape without that excuse — it
        # never fired, and would have relabelled paths no mount prefix vouches for.
        # Measured on a committed log: 65 lines carrying the layout, 55 folded by the
        # first pass, 10 by the second, 0 left.
        #
        # Not covered: a truncated fragment on a host with no mount prefix (a sweep run
        # natively on Linux would produce `"/home/alice/sideeye/spike/unkno"...`). The
        # check below greps for `/Users/` and `/home/`, so that case fails loudly there
        # rather than passing quietly here.
        #
        # `sed -i` writes a new file and renames, so an interrupt between the two leaves
        # `oracle.txt.bak` holding the unfolded text beside the folded one — untracked,
        # so check 2al's `git grep` would not see it. Removed first, so a leftover from a
        # previous interrupted sweep cannot survive this one either.
        for orc in "$ARTS/$artdir"/run/*/work/oracle.txt; do
            [ -f "$orc" ] || continue
            rm -f "$orc.bak"
            sed -i.bak -E \
                -e 's#/work/spike/unknown-rate/artifacts#@@SIDEEYE_WORK_MOUNT@@#g' \
                -e 's#(^|[^A-Za-z0-9_/])/[^ ")>,]*/spike/unknown-rate/artifacts#\1<repo>/spike/unknown-rate/artifacts#g' \
                -e 's#@@SIDEEYE_WORK_MOUNT@@#/work/spike/unknown-rate/artifacts#g' \
                -e 's#/run/host_virtiofs/[^ ")>,]*#<repo-truncated>#g' \
                "$orc"
            rm -f "$orc.bak"
        done
    else
        lrc=$(cat "$ARTS/$artdir/launcher-rc" 2>/dev/null || echo '?')
    fi
    if [ ! -f "$ARTS/$artdir/$rpath" ]; then
        # Fail-closed, the campaign runners' rule: a refusal is a result and
        # still writes a report; a MISSING report is an apparatus failure.
        echo "sweep: $id produced no report at $artdir/$rpath (launcher rc=$lrc)" >&2
        exit 2
    fi
    d=$(digest_for "$defines") || exit 2
    # Hashed here, from the file the trial just produced, which is what makes the column
    # mean "this sweep wrote it" rather than "a file of this name exists" (#349). The
    # existence check above has already run, and `sha256sum` is used three times before
    # this line, so neither a missing file nor a missing tool can reach it — a guard for
    # either would be the unreachable kind this change deleted from `count.py`.
    rsha=$(sha256sum "$ARTS/$artdir/$rpath" | cut -d' ' -f1)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$group" "$tool" "$class" "$judge" "$imgid" "$launcher $args" \
        "$d" "$artdir/$rpath" "$lrc" "$rsha" >> "$manifest"
done < "$corpus_stripped"
rm -f "$corpus_stripped"

mrows=$(wc -l < "$manifest" | tr -d ' ')
echo "sweep: expected rows=$expected_rows manifest rows=$mrows"
# Against THIS generation's expected set, not the whole corpus. Comparing to
# every corpus row was correct while one sweep covered everything and is
# wrong the moment a generation covers a subset: g2 selects 36 of 57 rows,
# so a complete run of it would have failed here with all 36 trials present.
[ "$expected_rows" = "$mrows" ] || { echo "sweep: manifest row count differs from generation $gen's expected set — incomplete sweep" >&2; exit 2; }
echo "sweep: done — artifacts under $ARTS"
