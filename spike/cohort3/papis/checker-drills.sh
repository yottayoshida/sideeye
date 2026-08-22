#!/bin/sh
# Per-leg falsification of the cohort-3 papis checker (every leg — and
# every distinctly-messaged branch of leg D — red once, separately,
# ATTRIBUTED by a branch-specific fragment), plus the two greens. Most
# of the reds are surgery-only shapes: the operation moves the whole
# document in with one atomic rename, so a half-built document is not
# engine-reachable. They are rehearsed anyway — a checker's teeth are
# for the damage the tool COULD do, and a branch that has never been
# seen red is not trusted (this repo's acceptance rule). States are
# fabricated with normal papis runs plus file surgery — no kill, no
# crash, no engine. Spawned through exec bits.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
P=/tmp/cohort3/papis
FAILS=0

drill() { # name want(pass|fail) state-dir expected-fragment
    name=$1; want=$2; st=$3; frag=$4
    out=$(SIDEEYE_STATE_DIR="$st" "$OPS/check.sh" 2>&1); rc=$?
    if [ "$want" = pass ] && [ "$rc" -eq 0 ]; then
        echo "drill ok   $name: checker green as required${out:+ — $out}"
    elif [ "$want" = fail ] && [ "$rc" -eq 1 ]; then
        case "$out" in
            *"$frag"*)
                echo "drill ok   $name: checker red in the intended branch; full checker output:"
                printf '%s\n' "$out" | sed 's/^/  | /' ;;
            *) echo "drill FAIL $name: red, but in the WRONG branch (wanted '$frag') — $out"; FAILS=$((FAILS+1)) ;;
        esac
    else
        echo "drill FAIL $name: rc=$rc, wanted $want — $out"
        FAILS=$((FAILS+1))
    fi
}

echo "== papis checker drills — $(papis --version 2>&1 | tr -d '\n') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIRS="$P/d-old $P/d-new $P/d-empty $P/d-noinfo $P/d-noattach $P/d-torn $P/d-bytes $P/d-exist $P/d-stray $P/d-guard"
rm -rf $DIRS
export XDG_CONFIG_HOME="$P/xdg" XDG_CACHE_HOME="$P/cache" HOME="$P/home"
export PAPIS_NP=0
"$OPS/setup.sh" > /dev/null 2>&1
echo "setup rc=$? (the library with its existing document, under the launcher's env)"

# green control, old side
cp -a "$P/lib" "$P/d-old"
drill "green-old" pass "$P/d-old" ""

# green control, new side: a completed add (rc checked; the document printed)
cp -a "$P/lib" "$P/d-new"
XDG_CONFIG_HOME="$P/xdg-new"; export XDG_CONFIG_HOME
mkdir -p "$P/xdg-new/papis"
sed "s|^dir = .*|dir = $P/d-new|" "$P/xdg/papis/config" > "$P/xdg-new/papis/config"
papis add --batch --from yaml "$P/probe-meta.yaml" --folder-name probe-doc "$P/fixture.txt" > /dev/null 2>&1
arc=$?
XDG_CONFIG_HOME="$P/xdg"; export XDG_CONFIG_HOME
echo "papis add rc=$arc (must be 0 for green-new to mean what it claims)"
[ "$arc" -eq 0 ] || { echo "drill FAIL green-new: papis add itself failed (rc=$arc)"; FAILS=$((FAILS+1)); }
echo "the document the add wrote:"
find "$P/d-new/probe-doc" -type f | sed "s|$P|P|" | sort
drill "green-new" pass "$P/d-new" ""

# leg D red: the directory arrived but nothing in it (the shape a
# non-atomic mkdir-then-fill would leave)
cp -a "$P/d-old" "$P/d-empty"; mkdir -p "$P/d-empty/probe-doc"
drill "D-red-empty-dir" fail "$P/d-empty" "its info.yaml is missing"

# leg D red: the attachment landed, the metadata did not. Papis itself
# is SILENT here (measured, trials state D: `papis list` ignores a
# directory with no info.yaml and exits 0) — leg D is the only leg that
# sees it.
cp -a "$P/d-new" "$P/d-noinfo"; rm "$P/d-noinfo/probe-doc/info.yaml"
drill "D-red-no-info" fail "$P/d-noinfo" "its info.yaml is missing"

# leg D red: the metadata landed, the attachment did not. Papis LISTS
# this document happily (measured, trials state E) — again only leg D
# sees it.
cp -a "$P/d-new" "$P/d-noattach"; rm "$P/d-noattach/probe-doc/fixture.txt"
drill "D-red-no-attachment" fail "$P/d-noattach" "its attachment fixture.txt is missing"

# leg D red: a torn info.yaml. It still parses as YAML but has lost the
# frozen fields; leg D must catch it BEFORE the reader, which was
# measured generating and persisting a random papis_id into exactly
# this state (trials state F).
cp -a "$P/d-new" "$P/d-torn"
head -c 40 "$P/d-new/probe-doc/info.yaml" > "$P/d-torn/probe-doc/info.yaml"
drill "D-red-torn-info" fail "$P/d-torn" "no longer carries the frozen title and papis_id"

# leg D red: the attachment truncated
cp -a "$P/d-new" "$P/d-bytes"
head -c 5 "$P/d-new/probe-doc/fixture.txt" > "$P/d-bytes/probe-doc/fixture.txt"
drill "D-red-attachment-bytes" fail "$P/d-bytes" "no longer holds the fixture's bytes"

# leg E red: the pre-existing document's attachment mutated
cp -a "$P/d-new" "$P/d-exist"
printf 'x' >> "$P/d-exist/existing-doc/existing.txt"
drill "E-red-existing-mutated" fail "$P/d-exist" "leg E: the existing document's attachment changed"

# leg R red: a third, structurally valid document the declaration does
# not account for — leg D and leg E both pass, and only papis's own
# reader shows it
cp -a "$P/d-new" "$P/d-stray"
cp -a "$P/d-new/probe-doc" "$P/d-stray/other-doc"
sed -i 's/^title: Probe$/title: Other/; s/^papis_id: probe0001$/papis_id: other0001/' "$P/d-stray/other-doc/info.yaml"
drill "R-red-stray-document" fail "$P/d-stray" "papis lists a different document set"

# leg C red: the outside-root fixture mutated
printf 'x' >> "$P/fixture.txt"
drill "C-red-fixture-mutated" fail "$P/d-new" "leg C: the outside-root fixture fixture.txt changed"
printf 'probe document, fixed bytes' > "$P/fixture.txt"

# guard red: the existing document is gone entirely
cp -a "$P/d-old" "$P/d-guard"; rm -rf "$P/d-guard/existing-doc"
drill "guard-red-existing-gone" fail "$P/d-guard" "the existing document's directory is missing"

rm -rf $DIRS "$P/xdg-new"
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
