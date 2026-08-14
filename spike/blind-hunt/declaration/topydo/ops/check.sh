#!/bin/sh
# Seal B artifact (ADR 0012): the declared checker for topydo 0.14, one dispatch
# per declared operation. This file is the concrete instantiation of the sealed
# wrapper-template.sh: a target query that must exit 0, output properties taken
# POSITIVELY from documentation, and file-format checks sanctioned by ADR 0012's
# todo.txt carve-out ("where the file format itself is normative public
# documentation ... the file *is* the documented contract").
#
# Written BLIND: no trace of topydo, no crash observation, no source, no bug
# tracker informed any line here. Provenance for every invariant is in
# ../declaration.md; the transcripts it cites are in ../transcripts/.
#
# Any edit to this file after Seal B marks the checker sighted (ADR 0012).
#
# Usage: check.sh <op>   (run by sideeye after crash + restart, in each world)
set -u

op=${1:?usage: check.sh <op>}
BIN=/usr/local/bin/topydo
S=/tmp/blind/hunt/$op/state
T=$S/todo.txt
D=$S/done.txt

fail() { echo "checker($op): $1" >&2; exit 1; }

# A task "appears" in a file only as a whitespace-delimited token on some line
# — an unanchored substring inside other text would not be the declared task
# (todo.txt spec: one task per line, fields whitespace-separated).
present() { [ -r "$1" ] && grep -Eq '(^|[[:space:]])'"$2"'([[:space:]]|$)' "$1"; }

# Per-operation declaration: which task texts must be conserved, and which
# optional legs apply. Conservation lists only tasks whose survival the
# documentation promises — del's target task 1 is deliberately absent from
# del's list (deletion is the documented effect, not a crash artifact).
conserve=""
leg_dup=""        # I-D2: completed/reverted task must not be in both files
leg_backup=""     # I-B: the documented backup-listing query must survive
case $op in
    add)      conserve="seed-task" ;;
    append)   conserve="water-plants" ;;
    del)      conserve="keep-me" ;;
    dep-add)  conserve="parent-task child-task" ;;
    dep-rm)   conserve="parent-task child-task" ;;
    depri)    conserve="water-plants" ;;
    do)       conserve="water-plants"; leg_dup=water-plants ;;
    ls)       conserve="water-plants" ;;
    postpone) conserve="water-plants" ;;
    pri)      conserve="water-plants" ;;
    revert)   conserve="water-plants"; leg_dup=water-plants; leg_backup=yes ;;
    sort)     conserve="zebra-task alpha-task" ;;
    tag)      conserve="water-plants" ;;
    *) fail "unknown operation '$op' — not in the declared inventory" ;;
esac

# I-Q — the target's own query succeeds after a crash + restart, and every
# line it prints keeps the documented list shape. The number may be padded
# (the documentation's example pads to width; the observed non-tty runs do
# not) — both are the documented shape.
# source: doc — `ls` tiddler ("Lists all (relevant) todo items"), GettingStarted
# list example (`|  1| (C) 2016-06-27 My first item`); observed non-tty shape
# `|1| 2026-08-13 seed-task` (transcripts/normal-runs.txt). Positive property,
# per wrapper-template rule 2.
out=$("$BIN" -t "$T" -d "$D" ls 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "ls exited $rc after the crash: $out"
if printf '%s\n' "$out" | grep -q .; then
    if printf '%s\n' "$out" | grep -v '^| *[0-9][0-9]*| ' | grep -q .; then
        fail "ls printed a line outside the documented '|<number>| <text>' shape: $out"
    fi
fi

# I-C — conservation across the pair of files. A task that existed before the
# operation is in the active list, or in the archive, but never in neither.
# source: doc — Archiving tiddler ("the completed item is *moved* to a separate
# text file"); todo.txt spec (one task per line, plain text); each subcommand's
# documented effect touches only the named task. The crash-consistency reading:
# interrupted or not, the operation has no documented license to destroy a task.
for want in $conserve; do
    if ! present "$T" "$want" && ! present "$D" "$want"; then
        fail "task '$want' is in neither todo.txt nor done.txt — lost"
    fi
done

# I-D2 — no duplication: after `do` ("moved to done.txt") or `revert` ("revert
# the todo and archive files to the state before"), the task lives in exactly
# one of the two files. Declared at lower severity than loss (declaration.md).
# source: doc — Archiving tiddler ("moved"), revert help text.
if [ -n "$leg_dup" ]; then
    if present "$T" "$leg_dup" && present "$D" "$leg_dup"; then
        fail "task '$leg_dup' is in both todo.txt and done.txt — duplicated"
    fi
fi

# I-F — every non-blank line of the archive is a completed task: lowercase x,
# a space, and the completion date directly after (YYYY-MM-DD, the spec's own
# date format).
# source: doc — todo.txt spec, Complete Tasks rule 1 ("A completed task starts
# with a lowercase x character") and rule 2 ("The date of completion appears
# directly after the x, separated by a space"); README ("topydo is fully
# todo.txt compliant").
if [ -r "$D" ]; then
    if grep -v '^x [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ' "$D" | grep -q .; then
        fail "done.txt contains a line that is not an 'x <YYYY-MM-DD> ...' completed task"
    fi
fi

# I-B — the documented backup-listing query survives the crash (revert only:
# the other operations run with backups disabled by the declared config).
# source: doc — revert tiddler ("You can retrieve a numbered list of all
# commands when running `revert ls`"). Exit code only; the backup file's own
# bytes are never read (its format is not documented).
if [ -n "$leg_backup" ]; then
    "$BIN" -t "$T" -d "$D" revert ls >/dev/null 2>&1 || \
        fail "revert ls exited nonzero — the backup store no longer answers"
fi

exit 0
