#!/bin/sh
# The blind-hunt phase driver: every campaign phase behind one entry point, each
# phase refusing to run until its preconditions hold.
#
# Why: the campaign's verdict tooling was already sealed and sound, but the
# sequencing between phases was typed by hand — and that is where a whole class
# of failures lived (a merge chained onto a checks *display*, a rebase continued
# past a failed assertion, a sweep against artifacts that disagreed with each
# other). This driver replaces the hand-typed chains. It never merges PRs and
# never commits: irreversible steps stay human, with their own read-then-act
# discipline. What it automates is refusal.
#
# Deliberately NOT a sealed artifact: it carries no verdict logic — everything it
# runs (sweep.sh, select.sh, check-config-paths.sh, verify-seals.sh) is sealed
# per campaign, and skipping the driver gains nothing but the chance to make the
# old mistakes by hand. Improving it mid-campaign is therefore legal.
#
# Usage: campaign-driver.sh <phase> <campaign-dir> [phase args]
#   status  <dir>                       what exists, what the next step is
#   sweep   <dir> <outdir>              preconditions + the container sweep
#   select  <dir>                       B3 locally, then the sealed selector
#   verify  <dir> <A> <B> [run] [rpts]  the campaign's own verify-seals
#   explore <dir> <seal-b-sha> <outdir> preconditions + the sealed runner
set -u

die() { echo "driver: $1" >&2; exit 2; }
[ $# -ge 2 ] || die "usage: campaign-driver.sh <phase> <campaign-dir> [args]"
phase=$1
dir=${2%/}
[ -d "$dir" ] || die "no campaign directory at $dir"
repo=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || die "$dir is not in a git repository"
name=$(basename "$dir")

# Shared preconditions ------------------------------------------------------

require_clean_tree() {
    if git -C "$repo" status --porcelain | grep -q .; then
        die "the worktree is dirty; campaign phases run from committed state only"
    fi
}

require_committed() {  # require_committed <repo-relative-path> <why>
    git -C "$repo" cat-file -e "HEAD:$1" 2>/dev/null || die "$1 is not in HEAD — $2"
}

require_consistency() {
    sh "$dir/check-config-paths.sh" "$dir" || die "sealed configs disagree with sealed invocations (the class that voided a seal)"
    sh "$repo/spike/check-sealed-campaigns.sh" "$repo" >/dev/null || die "check-sealed-campaigns fails on this tree"
}

engine_ready() {
    [ -x "$repo/zig-out/bin/sideeye" ] || die "no engine at zig-out/bin/sideeye — build from THIS revision first (zig build -Dtarget=aarch64-linux-gnu)"
    [ -r "$repo/zig-out/lib/libsideeye_shim.so" ] || die "no shim at zig-out/lib/libsideeye_shim.so"
}

image_id() {
    # `docker image inspect <name>` is flaky on this host's containerd store —
    # measured in one session: success, then "No such image" for a name that
    # `docker run` starts fine. Resolve by name first, fall back to the listing.
    id=$(docker image inspect sideeye-blindhunt:latest --format '{{.Id}}' 2>/dev/null) || id=""
    [ -n "$id" ] || id=$(docker images --filter reference=sideeye-blindhunt --format '{{.ID}}' 2>/dev/null | head -1)
    [ -n "$id" ] || die "container image sideeye-blindhunt not found"
    echo "$id"
}

rel() { echo "spike/$name/$1"; }

# Phases --------------------------------------------------------------------

case $phase in
status)
    echo "campaign: $name  (repo $repo)"
    for f in invocations.tsv sweep-manifest.json; do
        if git -C "$repo" cat-file -e "HEAD:$(rel $f)" 2>/dev/null; then
            echo "  committed: $f"
        elif [ -f "$dir/$f" ]; then
            echo "  WORKTREE ONLY (uncommitted): $f"
        else
            echo "  absent:    $f"
        fi
    done
    decl=$(ls -d "$dir"/declaration/*/ 2>/dev/null | head -1)
    echo "  declaration: ${decl:-absent}"
    if [ -f "$dir/voided-seals.txt" ]; then
        n=$(grep -cv '^\s*#\|^\s*$' "$dir/voided-seals.txt" 2>/dev/null || echo 0)
        echo "  voided seals on record: $n"
    fi
    ;;

sweep)
    out=${3:?usage: sweep <dir> <outdir-on-host>}
    require_clean_tree
    require_committed "$(rel invocations.tsv)" "campaign 2+ seals the rows at Seal A"
    [ -e "$out" ] && die "outdir $out already exists — a re-sweep must not overwrite a retained one"
    if [ -f "$dir/sweep-manifest.json" ] || git -C "$repo" cat-file -e "HEAD:$(rel sweep-manifest.json)" 2>/dev/null; then
        die "a sweep manifest already exists for $name; ADR 0012: the sweep runs once — a re-run needs a ledger entry and keeps both manifests"
    fi
    require_consistency
    engine_ready
    img=$(image_id)
    echo "driver: sweeping $name (image $img)"
    docker run --rm -v "$repo:/work" -e SWEEP_IMAGE="sideeye-blindhunt@$img" sideeye-blindhunt sh -c \
        "export HOME=/tmp/${name}/home; mkdir -p \$HOME; SIDEEYE=/work/zig-out/bin/sideeye sh /work/spike/$name/sweep.sh -i /work/spike/$name/invocations.tsv -o /work/${out#"$repo"/} -s /work/zig-out/lib/libsideeye_shim.so -r /usr/bin/strace" \
        || die "sweep failed"
    echo "driver: next — copy $out/sweep-manifest.json to $dir/, record the image id in the ledger (ledger-append.sh), commit both"
    ;;

select)
    require_committed "$(rel invocations.tsv)" "selection reads committed inputs only"
    require_committed "$(rel sweep-manifest.json)" "selection reads committed inputs only"
    # B3 locally, against HEAD's copies, before trusting the selector's answer.
    want=$(git -C "$repo" show "HEAD:$(rel sweep-manifest.json)" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("invocations_sha256",""))')
    got=$(git -C "$repo" show "HEAD:$(rel invocations.tsv)" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
    [ -n "$want" ] && [ "$want" = "$got" ] || die "committed manifest was not produced from committed invocations (B3)"
    if [ -f "$dir/burned.txt" ]; then
        sh "$dir/select.sh" "$dir/sweep-manifest.json" "$dir/priority.txt" "$dir/burned.txt"
    else
        sh "$dir/select.sh" "$dir/sweep-manifest.json" "$dir/priority.txt"
    fi
    ;;

verify)
    A=${3:?usage: verify <dir> <seal-a> <seal-b> [run-manifest] [reports-dir]}
    B=${4:?usage: verify <dir> <seal-a> <seal-b> [run-manifest] [reports-dir]}
    ( cd "$repo" && sh "$dir/verify-seals.sh" "$A" "$B" "${5:-}" "${6:-}" )
    ;;

explore)
    sealb=${3:?usage: explore <dir> <seal-b-sha> <outdir-on-host>}
    out=${4:?usage: explore <dir> <seal-b-sha> <outdir-on-host>}
    require_clean_tree
    head_sha=$(git -C "$repo" rev-parse HEAD)
    want_sha=$(git -C "$repo" rev-parse "$sealb^{commit}") || die "$sealb is not a commit"
    [ "$head_sha" = "$want_sha" ] || die "HEAD ($head_sha) is not Seal B ($want_sha); exploration runs from the seal, in a clean tree"
    [ -e "$out" ] && die "outdir $out already exists — each exploration gets a fresh one"
    require_consistency
    engine_ready
    runsh=$(ls "$dir"/declaration/*/run.sh 2>/dev/null | head -1)
    [ -n "$runsh" ] || die "no declaration/*/run.sh — the declaration phase has not produced a sealed runner"
    img=$(image_id)
    echo "driver: exploring from $head_sha (image $img)"
    docker run --rm -v "$repo:/work" \
        -e HEAD="$head_sha" -e CLEAN=true \
        -e OUT="/work/${out#"$repo"/}" \
        -e SIDEEYE=/work/zig-out/bin/sideeye -e SHIM=/work/zig-out/lib/libsideeye_shim.so \
        sideeye-blindhunt sh "/work/${runsh#"$repo"/}" || die "exploration runner failed"
    echo "driver: next — verify with: campaign-driver.sh verify $dir <seal-a> $sealb $out/run-manifest.json <reports>"
    ;;

*)
    die "unknown phase '$phase' (status | sweep | select | verify | explore)"
    ;;
esac
