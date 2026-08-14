#!/bin/sh
# Campaign 2 Seal A artifact (ADR 0012 via ADR 0015). The sweep harness, re-sealed:
# the candidates were installed during campaign 1 — ADR 0015 records that inheritance
# honestly — so what stays frozen here is the verdict logic and what it refuses to show.
#
# It prints ONE line per candidate:
#
#     <name> exit=<code> resolved=<yes|no>
#
# and nothing else. The full preflight report goes, unread, into the sealed directory
# and is hashed into the manifest. This is the point of the harness: preflight's report
# names refusal detectors and counts operations, and those correlate with how breakable
# a target looks. Selection may see the verdict; the declarer may not see the reasons
# until the invariants are sealed (Seal B).
#
# The reports are on the same disk as the person running this, so "unread" is a working
# rule, not a proof. The hash is narrower still: while the reports are retained, a later
# swap is detectable (verify-seals R2 recomputes them) — nothing more.
#
# Usage:
#   sweep.sh -i <invocations.tsv> -o <outdir> -s <shim> [-r <oracle>]
#
# The manifest is written under <outdir>; before Seal B it is COPIED to
# spike/blind-hunt2/sweep-manifest.json and committed (verify-seals.sh B1 expects it
# there, next to the SEALED invocations.tsv). The sealed reports never move and
# never get committed — only their hashes travel.
#
# Campaign 2's invocations.tsv is sealed at Seal A (its rows have been public since
# campaign 1; ADR 0015 §3) and the A2 no-touch set keeps it frozen between the seals.
# The rows were verified resolvable in the pinned image before the seal — no target
# was executed for that check.
#
# Columns (tab-separated, one candidate per line, in the sealed priority order):
#   name <TAB> binary <TAB> state_dir <TAB> setup_cmd <TAB> operation_cmd
#
# No column may be empty — a target with no setup writes `-`. Tab is IFS whitespace,
# and POSIX read collapses consecutive whitespace separators: an empty field does not
# survive the split, it shifts every later column left (measured; the five-field guard
# below caught it as a missing column).
set -u

SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}

inv="" out="" shim="" oracle=""
while [ $# -gt 0 ]; do
    case $1 in
        -i) inv=$2; shift 2 ;;
        -o) out=$2; shift 2 ;;
        -s) shim=$2; shift 2 ;;
        -r) oracle=$2; shift 2 ;;
        *) echo "sweep: unknown argument: $1" >&2; exit 2 ;;
    esac
done
# The oracle is not optional (R1 finding: the ADR's predicate requires it; an
# oracle-less sweep would accept on a weaker recording claim than the campaign scores).
[ -n "$inv" ] && [ -n "$out" ] && [ -n "$shim" ] && [ -n "$oracle" ] || {
    echo "usage: sweep.sh -i <invocations.tsv> -o <outdir> -s <shim> -r <oracle>" >&2
    exit 2
}
[ -r "$inv" ] || { echo "sweep: cannot read $inv" >&2; exit 2; }

sealed=$out/sealed-reports
mkdir -p "$sealed" || exit 2
manifest=$out/sweep-manifest.json

# One digest tool or the other; a sweep that silently skipped hashing would leave the
# "not swapped afterwards" claim with nothing behind it.
if command -v sha256sum >/dev/null 2>&1; then
    digest() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
    digest() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
    echo "sweep: no sha256 tool; refusing to run without a way to hash the sealed reports" >&2
    exit 2
fi

# The manifest records the hash of the invocations it ran against (campaign-1 R1:
# without this, invocations could be tuned against exit codes between runs and only
# the final spelling committed). verify-seals.sh requires the committed
# invocations.tsv to match. Campaign 2 adds the execution identity (campaign-2 R1
# finding 4): the engine's version string and the SHA-256 of the binary and shim
# that actually swept, plus the operator-supplied image name (SWEEP_IMAGE env,
# self-reported). The exploration's run manifest records the same fields, so the
# two phases are comparable from committed artifacts — this binds them to each
# other, not to a source tree, and ADR 0015 says exactly that.
engine_version=$("$SIDEEYE" version 2>/dev/null | head -1)
[ -n "$engine_version" ] || engine_version="unknown"
printf '{\n  "schema": "sideeye/blind-hunt-sweep",\n  "invocations_sha256": "%s",\n  "engine": "%s",\n  "engine_sha256": "%s",\n  "shim_sha256": "%s",\n  "image": "%s",\n  "candidates": [\n' \
    "$(digest "$inv")" "$engine_version" "$(digest "$SIDEEYE")" "$(digest "$shim")" "${SWEEP_IMAGE:-unrecorded}" > "$manifest"
first=1
lineno=0

while IFS='	' read -r name binary state setup operation; do
    lineno=$((lineno + 1))
    case "$name" in ''|'#'*) continue ;; esac
    [ -n "$binary" ] && [ -n "$state" ] && [ -n "$setup" ] && [ -n "$operation" ] || {
        echo "sweep: line $lineno of $inv is missing a column (an empty field must be spelled -)" >&2
        exit 2
    }
    [ "$setup" = "-" ] && setup=""

    # The container-resolution leg of the predicate: every command the define names —
    # the binary, the setup's first word, the operation's first word, and the shim —
    # must resolve to an absolute path in the environment this sweep runs in. The sweep
    # runs inside the pinned container, so "resolves here" is "lives in the image" by
    # construction; a saved case pins absolute paths, and a target reached through a
    # wrapper outside the image could not replay later (ADR 0012 decision 2).
    # R1 finding: the first version checked only $binary and left setup/operation/shim
    # unexamined — three of the four ways a define escapes the image.
    resolved=yes
    for word in "$binary" "${setup%% *}" "${operation%% *}"; do
        [ -n "$word" ] || continue
        p=$(command -v "$word" 2>/dev/null) || p=""
        case "$p" in /*) : ;; *) resolved=no ;; esac
    done
    # The shim is loaded, not executed — absolute and readable is its resolution test
    # (command -v would demand an execute bit a shared object need not carry).
    case "$shim" in
        /*) [ -r "$shim" ] || resolved=no ;;
        *) resolved=no ;;
    esac

    # Refuse, never delete: a state directory that already exists belongs to some
    # earlier run, and a harness that silently clears it would be deciding what to
    # destroy. Fresh paths are the caller's job. (Also measured: the first version
    # used rm -rf and was blocked by a host-side guard — refusal has no such edge.)
    if [ -e "$state" ]; then
        echo "sweep: state dir already exists: $state — give each sweep a fresh path" >&2
        exit 2
    fi
    mkdir -p "$state" || exit 2
    set -- preflight --state "$state" --operation "$operation" --shim "$shim"
    [ -n "$setup" ] && set -- "$@" --setup "$setup"
    [ -n "$oracle" ] && set -- "$@" --oracle "$oracle"

    # The report never reaches this terminal. Redirected before the call, not filtered
    # after it: a filter is one broken pattern away from printing everything.
    "$SIDEEYE" "$@" > "$sealed/$name.report" 2>&1
    rc=$?

    echo "$name exit=$rc resolved=$resolved"

    [ "$first" = 1 ] || printf ',\n' >> "$manifest"
    first=0
    printf '    {"name": "%s", "exit": %d, "resolved": "%s", "report_sha256": "%s"}' \
        "$name" "$rc" "$resolved" "$(digest "$sealed/$name.report")" >> "$manifest"
done < "$inv"

printf '\n  ]\n}\n' >> "$manifest"
[ "$first" = 0 ] || {
    echo "sweep: no candidates were swept; an empty manifest would read as 'all refused'" >&2
    exit 2
}
echo "sweep: manifest written to $manifest (reports sealed in $sealed)"
