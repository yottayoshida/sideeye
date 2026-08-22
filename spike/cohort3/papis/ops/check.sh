#!/bin/sh
# Cohort-3 papis define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `papis add`, and the library holds either the old
# document set or the old set plus the COMPLETE new document, with
# papis's own reader agreeing about which. Legs, in this order:
# guard (the library and the existing document are there), leg D (the
# new document is all-or-nothing: absent, or present with both members,
# the attachment's frozen bytes and the frozen title/papis_id), leg E
# (the existing document is conserved), leg C (the outside-root
# fixtures are unmutated), and last leg R (papis's own reader lists
# exactly the documents leg D found).
#
# The reader runs LAST on purpose, and it is the only leg that can
# write: the pre-define trials measured `papis list` — by itself, with
# no other command run — generating and PERSISTING a papis_id into a
# document whose info.yaml lost that field, and two byte-identical
# torn states received different ids, so the value is random rather
# than derived (pre-define-trials.txt, states F and H/I/J). A byte
# assertion after the reader would be judging the checker's own side
# effect, so every structural and byte assertion precedes it.
#
# No documented recovery is applied, because the trials measured
# papis's repair command — `papis doctor -a`, with the selection flag
# its help documents — and none of what it does is a recovery here:
# it is red on the untouched baseline (six type errors over the two
# healthy documents, rc 0 while saying so), its one applicable fix
# "repairs" a lost attachment by REMOVING the file from the document
# ("[FIX] Removing file from document"), and on a torn info.yaml it
# dies with an uncaught AttributeError. A command that is red before
# the operation, that resolves data loss by forgetting the data, and
# that crashes on the damage it would be called for, is not the
# documented recovery the cohort rule asks for. Measured, not assumed:
# pre-define-trials.txt, states A–G.
#
# The library papis reads is $SIDEEYE_STATE_DIR, so the config is
# written per invocation with that path (its content is otherwise the
# frozen one). Cache and config live in the per-invocation temp dir so
# the checker cannot pollute the ambient it judges; the library's
# cache layer is off in the config either way.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
P=/tmp/cohort3/papis
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/papis"
cat > "$T/papis/config" <<EOF
[settings]
time-stamp = False
use-cache = False
default-library = probe

[probe]
dir = $S
EOF
export XDG_CONFIG_HOME="$T" XDG_CACHE_HOME="$T/cache" HOME="$P/home"
export PAPIS_NP=0

fail() { echo "checker(papis-add): $*"; exit 1; }

# yaml_fields <file> — prints "title|papis_id" as papis's own YAML
# parser sees them; nonzero when the file does not parse.
yaml_fields() {
    python3 -c '
import sys, yaml
with open(sys.argv[1], "rb") as fh:
    d = yaml.safe_load(fh) or {}
if not isinstance(d, dict):
    raise SystemExit("info.yaml is not a mapping")
print("%s|%s" % (d.get("title"), d.get("papis_id")))
' "$1" 2> "$T/yaml.err"
}

# ---- guard: the library holds what a library of this define can hold ------
# The entry enumeration is the guard the accepted probe had and the
# first draft of this checker dropped: without it a stray entry, or a
# probe-doc that is a dangling symlink or a plain file, walks past
# every leg (leg D's -e is false for a dangling link, and leg R then
# expects the old set).
[ -d "$S" ] || fail "the library directory is missing"
entries=$(ls -A "$S" | sort | tr '\n' ' ')
case "$entries" in
    'existing-doc ')            probe_present=no ;;
    'existing-doc probe-doc ')  probe_present=yes ;;
    *) fail "the library holds entries this operation cannot produce (got: $entries)" ;;
esac
[ -d "$S/existing-doc" ] || fail "the existing document's directory is missing from the library"
[ -f "$S/existing-doc/info.yaml" ] || fail "the existing document has lost its info.yaml"
[ -f "$S/existing-doc/existing.txt" ] || fail "the existing document has lost its attachment"

# ---- leg D: the new document is all-or-nothing ----------------------------
# Presence comes from the guard's entry list, not from a -e test: a
# dangling symlink named probe-doc is listed by ls and invisible to
# -e, and the two legs that branch on presence must never disagree
# about it.
if [ "$probe_present" = yes ]; then
    { [ -d "$S/probe-doc" ] && [ ! -L "$S/probe-doc" ]; } \
        || fail "leg D: the library holds a probe-doc entry that is not a plain directory"
    [ -f "$S/probe-doc/info.yaml" ] || fail "leg D: probe-doc is present but its info.yaml is missing"
    [ -f "$S/probe-doc/fixture.txt" ] || fail "leg D: probe-doc is present but its attachment fixture.txt is missing"
    printf 'probe document, fixed bytes' | cmp -s - "$S/probe-doc/fixture.txt" \
        || fail "leg D: probe-doc's attachment no longer holds the fixture's bytes"
    got=$(yaml_fields "$S/probe-doc/info.yaml")
    rc=$?
    [ "$rc" -eq 0 ] || fail "leg D: probe-doc/info.yaml does not parse as YAML: $(head -c 200 "$T/yaml.err")"
    [ "$got" = "Probe|probe0001" ] || fail "leg D: probe-doc/info.yaml no longer carries the frozen title and papis_id (title|papis_id = $got)"
fi

# ---- leg E: the existing document is conserved ----------------------------
printf 'existing document, fixed bytes' | cmp -s - "$S/existing-doc/existing.txt" \
    || fail "leg E: the existing document's attachment changed"
got=$(yaml_fields "$S/existing-doc/info.yaml")
rc=$?
[ "$rc" -eq 0 ] || fail "leg E: the existing document's info.yaml does not parse as YAML: $(head -c 200 "$T/yaml.err")"
[ "$got" = "Existing|existing0001" ] || fail "leg E: the existing document's info.yaml no longer carries its title and papis_id (title|papis_id = $got)"

# ---- leg C: conservation of the outside-root fixtures ---------------------
printf 'probe document, fixed bytes' | cmp -s - "$P/fixture.txt" \
    || fail "leg C: the outside-root fixture fixture.txt changed"
printf 'existing document, fixed bytes' | cmp -s - "$P/existing.txt" \
    || fail "leg C: the outside-root fixture existing.txt changed"
printf 'title: Probe\nauthor: Probe Author\nyear: 2026\npapis_id: probe0001\n' | cmp -s - "$P/probe-meta.yaml" \
    || fail "leg C: the outside-root metadata fixture probe-meta.yaml changed"
printf 'title: Existing\nauthor: Probe Author\npapis_id: existing0001\n' | cmp -s - "$P/existing-meta.yaml" \
    || fail "leg C: the outside-root metadata fixture existing-meta.yaml changed"

# ---- leg R: papis's own reader agrees with what is on disk ----------------
# stdout carries only the formatted lines (measured; the indexing INFO
# goes to stderr).
timeout 120 papis list --all --format '{doc[title]} {doc[papis_id]}' > "$T/got" 2> "$T/list.err"
rc=$?
if [ "$rc" -ne 0 ]; then
    tnote=""; case "$rc" in 124|137) tnote="; this step timed out" ;; esac
    fail "leg R: papis list failed (rc=$rc$tnote): $(head -c 200 "$T/list.err")"
fi
if [ "$probe_present" = yes ]; then
    printf 'Existing existing0001\nProbe probe0001\n' > "$T/want"
else
    printf 'Existing existing0001\n' > "$T/want"
fi
sort "$T/got" > "$T/got.sorted"
sort "$T/want" > "$T/want.sorted"
cmp -s "$T/got.sorted" "$T/want.sorted" \
    || fail "leg R: papis lists a different document set than the library holds — got [$(tr '\n' ';' < "$T/got.sorted")] want [$(tr '\n' ';' < "$T/want.sorted")]"

exit 0
