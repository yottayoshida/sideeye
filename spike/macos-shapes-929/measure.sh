#!/bin/sh
# measure.sh <sideeye binary> <out dir> <label> — the three shapes SELECTION.md fixed, on one
# macOS host. Run by .github/workflows/spike-macos-shapes.yml; the record is copied into the
# tree by hand.
set -u

usage="usage: measure.sh <sideeye binary> <out dir> <label>"
se=${1:?$usage}
out=${2:?$usage}/${3:?$usage}
here=$(cd "$(dirname "$0")" && pwd)
root=$HOME/s929
mkdir -p "$out"
: > "$out/summary.tsv"

gsed=$(brew --prefix)/bin/gsed
git=$(brew --prefix)/bin/git
{
    echo "label:     $3"
    echo "macOS:     $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "uname:     $(uname -srm)"
    echo "sideeye:   $("$se" version 2>&1)"
    echo "gsed:      $("$gsed" --version 2>&1 | head -1)"
    echo "git:       $("$git" --version 2>&1)"
    for b in "$gsed" "$git" /usr/bin/plutil; do
        echo "codesign of $b:"; codesign -dv "$b" 2>&1 | sed 's/^/    /'
        echo "file of $b: $(file -b "$b")"
    done
    echo "user:      $(id -un) (uid $(id -u))"
} > "$out/env.txt"
if sudo -n true 2> "$out/sudo.txt"; then echo "sudo:      no password asked" >> "$out/env.txt"
else echo "sudo:      asks for a password — the oracle runs below are a missing privilege" >> "$out/env.txt"; fi

# Not `name`: sh has no local variables, and shape() reads its own `name` after each call.
timed() {   # timed <label> <command...> — run, record exit and seconds
    t_label=$1; shift
    t0=$(date +%s)
    "$@" > "$out/$t_label.txt" 2>&1
    t_rc=$?
    t1=$(date +%s)
    verdict=$(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR|PREFLIGHT)' "$out/$t_label.txt")
    printf '%s\texit %s\t%ss\t%s\n' "$t_label" "$t_rc" "$((t1 - t0))" "${verdict:-(no verdict line)}" >> "$out/summary.tsv"
    return "$t_rc"
}

shape() {   # shape <name> <operation> <setup> <check>
    name=$1 op=$2 setup=$3 check=$4
    st=$root/$name/st
    ctl=$root/$name/control
    rm -rf "$root/$name" && mkdir -p "$st" "$ctl"
    # The control: the setup's state, broken by hand, must fail the checker before any verdict counts.
    SIDEEYE_STATE_DIR=$ctl sh -c "$setup" > "$out/$name-control.txt" 2>&1
    sh "$here/$name/break.sh" "$ctl" >> "$out/$name-control.txt" 2>&1
    if SIDEEYE_STATE_DIR=$ctl sh -c "$check" >> "$out/$name-control.txt" 2>&1; then
        printf '%s-control\tthe checker PASSED the broken state: this pair proves nothing\n' "$name" >> "$out/summary.tsv"
    else
        printf '%s-control\tthe checker fails the broken state, as it must\n' "$name" >> "$out/summary.tsv"
    fi
    w=$(mktemp -d "${TMPDIR:-/tmp}/shapes-$name-XXXXXX")
    # preflight takes no --oracle-fs-usage, so on macOS it cannot accept a process boundary; the
    # oracle's explore runs either way, and summary.tsv says whether #929's protocol reached it.
    timed "$name-preflight" "$se" preflight --twice --state "$st" --setup "$setup" --operation "$op" \
        --work "$w/p" --json "$out/$name-preflight.json"
    if grep -q "recording accepted" "$out/$name-preflight.txt"; then
        printf '%s-oracle\tthe preflight accepted the recording: #929 protocol\n' "$name" >> "$out/summary.tsv"
    else
        printf '%s-oracle\tthe preflight refused: run beyond #929 protocol\n' "$name" >> "$out/summary.tsv"
    fi
    timed "$name-oracle" "$se" explore --state "$st" --setup "$setup" --operation "$op" --check "$check" \
        --oracle-fs-usage --work "$w/o" --json "$out/$name-oracle.json"
    timed "$name-unverified" "$se" explore --state "$st" --setup "$setup" --operation "$op" --check "$check" \
        --allow-unverified --work "$w/u" --json "$out/$name-unverified.json"
    for f in "$w"/*/cases/*.json; do
        [ -f "$f" ] || continue
        cp "$f" "$out/$name-case-$(basename "$(dirname "$(dirname "$f")")")-$(basename "$f")"
        timed "$name-replay-$(basename "$(dirname "$(dirname "$f")")")" "$se" replay "$f" --work "$w/r"
    done
}

shape sed "$gsed -i s/mode=old/mode=new/ $root/sed/st/app.conf" "$here/sed/setup.sh" "$here/sed/check.sh"
shape git "$git -C $root/git/st/repo gc --quiet" "$here/git/setup.sh $git" "$here/git/check.sh $git"
shape plutil "/usr/bin/plutil -convert binary1 $root/plutil/st/prefs.plist" "$here/plutil/setup.sh" "$here/plutil/check.sh"
cat "$out/summary.tsv"
