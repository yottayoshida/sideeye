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
# write: the pre-define trials measured papis generating and
# PERSISTING a fresh random papis_id into a document whose info.yaml
# lost that field (trials.txt, state F). A byte assertion after the
# reader would be judging the checker's own side effect, so every
# structural and byte assertion precedes it.
#
# No documented recovery is applied, because the trials found none that
# applies: `papis doctor` — papis's repair command — retrieves nothing
# non-interactively in a multi-document library (it falls to the
# picker: "Cannot show the picker... No documents retrieved", rc 0),
# reports the same three type errors on the untouched pre-state
# baseline, and auto-fixes zero of them. That is measured, not assumed;
# proposals.md carries the transcript reference.
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

# ---- guard: the library and the existing document are there ---------------
[ -d "$S" ] || fail "the library directory is missing"
[ -d "$S/existing-doc" ] || fail "the existing document's directory is missing from the library"
[ -f "$S/existing-doc/info.yaml" ] || fail "the existing document has lost its info.yaml"
[ -f "$S/existing-doc/existing.txt" ] || fail "the existing document has lost its attachment"

# ---- leg D: the new document is all-or-nothing ----------------------------
if [ -e "$S/probe-doc" ]; then
    [ -d "$S/probe-doc" ] || fail "leg D: probe-doc exists but is not a directory"
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
if [ -e "$S/probe-doc" ]; then
    printf 'Existing existing0001\nProbe probe0001\n' > "$T/want"
else
    printf 'Existing existing0001\n' > "$T/want"
fi
sort "$T/got" > "$T/got.sorted"
sort "$T/want" > "$T/want.sorted"
cmp -s "$T/got.sorted" "$T/want.sorted" \
    || fail "leg R: papis lists a different document set than the library holds — got [$(tr '\n' ';' < "$T/got.sorted")] want [$(tr '\n' ';' < "$T/want.sorted")]"

exit 0
