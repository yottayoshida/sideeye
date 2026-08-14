#!/bin/sh
# Campaign-2 Seal B artifact (ADR 0012 via ADR 0015): the declared checker for
# khard 0.21.0, one dispatch per declared operation. Instantiates the sealed
# wrapper template: the target's own query must exit 0 with a documented output
# property stated POSITIVELY, and file-level checks use ADR 0012's normative-
# format carve-out — khard.conf(5): "khard expects the vCard files to hold only
# one VCARD record each and end in a .vcf extension"; the vCard structure
# itself is RFC 6350 (BEGIN:VCARD/END:VCARD, FN required in every vCard).
#
# Written BLIND: no trace of khard, no crash observation, no source, no bug
# tracker informed any line here. Provenance for every invariant is in
# ../declaration.md; the transcripts it cites are in ../transcripts/.
# Any edit after Seal B marks the checker sighted (ADR 0012).
#
# Usage: check.sh <op>   (run by sideeye after crash + restart, in each world)
set -u

op=${1:?usage: check.sh <op>}
here=/work/spike/blind-hunt2/declaration/khard/ops
C=$here/khard-$op.conf
S=/tmp/blind2/hunt/$op/state

fail() { echo "checker($op): $1" >&2; exit 1; }

case $op in new|remove|move|copy) : ;; *) fail "unknown operation '$op' — not in the declared inventory" ;; esac

# I-Q — the target's own query survives the crash. Grace is present in every
# declared post-state, so the listing must succeed and show her.
# source: doc — khard-subcommands(1) `list`: "list all (selected) contacts";
# output columns observed in normal runs (Index/Name header, one row per
# contact). Positive property, per wrapper-template rule 2.
out=$(khard -c "$C" list < /dev/null 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "list exited $rc after the crash: $out"
printf '%s\n' "$out" | grep -q "Grace Hopper" || fail "list does not show the conserved contact: $out"

# I-C — conservation, on the files (carve-out): the bystander Grace, whom no
# declared operation's documentation licenses to touch, has exactly one vCard
# across the whole store.
# source: doc — khard.conf(5) one-VCARD-per-.vcf; RFC 6350 §6.2.1 (FN); each
# subcommand's documented effect names only its subject.
grace_count=$(grep -l "^FN:Grace Hopper" "$S"/main/*.vcf "$S"/second/*.vcf 2>/dev/null | wc -l | tr -d ' ')
[ "$grace_count" = 1 ] || fail "conserved contact Grace has $grace_count vCards, expected exactly 1"

# Per-operation invariants over the subject, Ada.
ada_main=$(grep -l "^FN:Ada Lovelace" "$S"/main/*.vcf 2>/dev/null | wc -l | tr -d ' ')
ada_second=$(grep -l "^FN:Ada Lovelace" "$S"/second/*.vcf 2>/dev/null | wc -l | tr -d ' ')
ada_total=$((ada_main + ada_second))
case $op in
    new)
        # The operation creates Ada; a crashed create may leave her present or
        # absent (the payload is not protected — campaign-1 add precedent),
        # but never duplicated.
        # source: doc — `new`: "create a new contact" (one).
        [ "$ada_total" -le 1 ] || fail "new left $ada_total Ada vCards, more than the one it creates"
        ;;
    remove)
        # Deletion is the documented effect; the subject may be present (not
        # yet removed) or absent (removed), never duplicated.
        # source: doc — `remove`: "remove a contact".
        [ "$ada_total" -le 1 ] || fail "remove left $ada_total Ada vCards"
        ;;
    move)
        # THE cross-file window. "move a contact to a different addressbook":
        # one contact, one store — after a crash Ada is in main or in second,
        # never in neither (lost) and never in both (duplicated).
        # source: doc — `move` synopsis; severity pre-registered in
        # declaration.md (loss over duplication).
        [ "$ada_total" -eq 0 ] && fail "moved contact Ada is in neither addressbook — lost"
        [ "$ada_total" -ge 2 ] && fail "moved contact Ada is in $ada_total places — duplicated"
        ;;
    copy)
        # "copy a contact to a different addressbook": the source stays. Ada
        # must still be in main; the copy in second may or may not exist yet.
        # source: doc — `copy` synopsis (copy, not move).
        [ "$ada_main" -eq 1 ] || fail "copy source Ada is gone from main ($ada_main vCards)"
        [ "$ada_second" -le 1 ] || fail "copy left $ada_second copies in second"
        ;;
esac

# I-F — store shape, from the normative format: every .vcf present is a single
# complete vCard (BEGIN:VCARD first line, exactly one BEGIN, an END:VCARD, and
# the mandatory FN property).
# source: doc — khard.conf(5) "only one VCARD record each"; RFC 6350 §6.1.1/6.1.2
# (BEGIN/END delimiters), §6.2.1 (FN is REQUIRED).
for f in "$S"/main/*.vcf "$S"/second/*.vcf; do
    [ -e "$f" ] || continue
    head -1 "$f" | grep -q "^BEGIN:VCARD" || fail "$f does not start with BEGIN:VCARD"
    [ "$(grep -c "^BEGIN:VCARD" "$f")" = 1 ] || fail "$f holds more than one VCARD record"
    grep -q "^END:VCARD" "$f" || fail "$f has no END:VCARD"
    grep -q "^FN:" "$f" || fail "$f has no FN property"
done

# I-B (recovery path, ADR 0015 §2): khard's documentation names no recovery,
# undo, or repair command — the sealed transcripts of khard(1),
# khard-subcommands(1), khard.conf(5), the command-line page and the scripting
# page contain none — so the recovery-path rule discharges vacuously
# (declaration.md, "The recovery-path rule").

exit 0
