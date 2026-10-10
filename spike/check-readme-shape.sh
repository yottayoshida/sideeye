#!/bin/sh
# Hold the README to the shape it was cut to: the shortest path to a first verdict.
#
# Usage: check-readme-shape.sh <README.md>
#
# The README is the only sideeye document the onboarding clock hands its driver
# (spike/onboarding-clock/PROTOCOL.md: a network-off box holding README.md alone), so what
# the page has to keep is what that driver leaned on to reach a verdict. Run 1 named it
# (spike/onboarding-clock/RESULTS.md, "What the run taught about the README", and the
# driver's own account above it — both sections sit inside run 1, which spans that file to
# line 147; run 2's sections carry the number, the audit and the permission layer, and no
# lessons about the page). Run 1 read the page as it stood at its clock_start — 160 lines and
# 9,963 bytes, against the v0.10.0 tarball — so this list is what a driver needed from a page
# about 1.7 times the size of this one, which is a reason the re-run criterion 6 owes matters, not a
# substitute for it. Each check below is one of those seven, pinned by a
# sentence that carries its meaning rather than by a flag name a table could list without
# explaining — `--allow-unverified` alone in a flag list would pass a name check and tell
# the reader nothing about when it is needed.
#
# The size bound is the other half. The page had grown to 33 KB by writing each decision's
# record into it — issue numbers, ADR numbers, the reason behind each refusal — and those have
# homes of their own (DESIGN.md, docs/, docs/adr/). The first bound was the page's own size
# plus a fixed slack, and it moved with the page: each sentence an issue added raised it (the
# record of those additions is in this file's history), so it recorded the growth and stopped
# none of it — 113 lines and 1,296 words on 2026-10-03, 135 lines and 1,569 words six days
# later. Since 2026-10-10 the bound is fixed where the owner put it: 100 lines and 800 words,
# as `wc -l` and `wc -w` count them. That is omamori's README (80 lines, 746 words) plus the
# demo block this page carries and omamori's does not, and 40 words above the bound
# lossless-compaction's tests hold (760): the first cut to 760 had to drop the limits the
# engine's next_step strings send a reader to (class_wall, syscalls_may_have_killed,
# threads_limit name 'What the target has to be'), and putting them back costs the 40. A
# sentence that does not fit moves another out, to the page its reason lives on, or goes
# there itself and leaves a link. Words rather than bytes or lines alone, because a line
# bound is escaped by writing longer lines, which is what this page did. The demo block, the
# toml and the checker are inside the count: they are the page's, not slack.
#
# Sunset: if this has not failed once by 2026-12-04, delete it and its CI step.
set -u

if [ $# -ne 1 ]; then
    echo "usage: check-readme-shape.sh <README.md>" >&2
    exit 2
fi
R=$1
[ -f "$R" ] || { echo "FAIL $R is not a file" >&2; exit 1; }

fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
has() { grep -qF -e "$1" "$R"; }

lines=$(wc -l < "$R" | tr -d ' ')
words=$(wc -w < "$R" | tr -d ' ')
if [ "$lines" -le 100 ]; then ok "length: $lines lines, at most 100"; else bad "length: $lines lines, over 100 — move a sentence to the page its reason lives on"; fi
if [ "$words" -le 800 ]; then ok "size: $words words, at most 800"; else bad "size: $words words, over 800 — move a sentence to the page its reason lives on"; fi
n=$(grep -cE '#[0-9]+' "$R")
if [ "$n" -eq 0 ]; then ok "no issue numbers"; else bad "$n line(s) carry an issue number; the record belongs in the page the reason lives on"; fi
n=$(grep -cE 'ADR[ -][0-9]{4}' "$R")
if [ "$n" -eq 0 ]; then ok "no ADR numbers"; else bad "$n line(s) carry an ADR number; link docs/adr/ from the page the reason lives on"; fi

# 1. The demo, and that its exit 1 is success.
if has 'sideeye demo' && has 'Exit 1'; then ok "the demo, and its exit 1 read as success"
else bad "the demo or the sentence saying its exit 1 is success is gone"; fi

# 2. The three commands, in the order a reader meets them.
d=$(grep -n '^\$ sideeye demo' "$R" | head -1 | cut -d: -f1)
p=$(grep -n '^\$ sideeye preflight' "$R" | head -1 | cut -d: -f1)
e=$(grep -n '^\$ sideeye explore' "$R" | head -1 | cut -d: -f1)
if [ -n "$d" ] && [ -n "$p" ] && [ -n "$e" ] && [ "$d" -lt "$p" ] && [ "$p" -lt "$e" ]; then
    ok "demo, preflight, explore, in that order"
else
    bad "the three commands are missing or out of order (demo:${d:-none} preflight:${p:-none} explore:${e:-none})"
fi

# 3. When --allow-unverified is needed, not only that it exists. The condition, not the
# spelling of it: run 1's driver got the condition from preflight's own warning rather than
# from the page, so what the page owes the reader is that the flag is the no-second-witness
# case — "oracle" and "witness" are both ways to say it, and pinning only the first would go
# red on a rewording that kept the meaning.
if grep -F -e '--allow-unverified' "$R" | grep -qE 'oracle|witness'; then ok "--allow-unverified, with the no-oracle condition beside it"
else bad "--allow-unverified is gone, or no longer says it is the case with no second witness"; fi

# 4. How to write a check: the claim against the observable truth.
if has 'the claim and the observable truth disagreeing'; then ok "the checker's philosophy"
else bad "the sentence on what a check compares is gone"; fi

# 5. That a checker is falsified before it is trusted.
if has 'refuses to trust a checker it has not seen fail'; then ok "the checker is seen to fail before it is trusted"
else bad "the sentence on falsifying the checker first is gone"; fi

# 6. How command strings are split.
if has 'split on spaces'; then ok "command strings split on spaces"
else bad "the splitting rule for command strings is gone"; fi

# 7. --shim and --work, which run 1's driver found only in the Example.
if has '`--shim`' && has '`--work`'; then ok "--shim and --work"
else bad "--shim or --work is gone"; fi

# 8. A reader who has only the tarball can start it. Not one of run 1's seven: the page
# carried a working install section then, so the driver never had to name it. The box holds
# README.md and one release tarball, so this is the other half of "reaches a verdict from the
# README alone" — a brew line alone is unusable there.
if has 'tar xzf' && has './sideeye'; then ok "the release artifact can be started from the page"
else bad "the untar-and-run path is gone; the onboarding box has no other way to start the tarball"; fi

# 9. The one named exception to "never a silent PASS" sits in the sentence that makes that
# promise (ADR 0032: a reader meets the exception where the promise is made). The sentence
# runs from the phrase to the next ". " or the end of its line; the exception is named by the
# field the JSON report counts it in. Not one of run 1's seven either: added when #714 shortened
# the exception to a clause, so that a later edit cannot move it out of the sentence again.
promise_line=$(grep -F 'never a silent PASS' "$R" | head -1)
promise_rest=${promise_line#*never a silent PASS}
promise_sentence=$(printf '%s\n' "$promise_rest" | sed 's/\. .*//')
if [ -n "$promise_line" ] && printf '%s\n' "$promise_sentence" | grep -qF 'paths_attributed_to_rename'; then
    ok "the promise names its one exception in the same sentence"
else
    bad "\"never a silent PASS\" is gone, or its sentence no longer names paths_attributed_to_rename"
fi

# 10. The command that turns a saved FAIL into an upstream report (#709). Not one of run 1's seven:
# the step after a first verdict, which the page names in the paragraph after it.
if has 'sideeye evidence'; then ok "sideeye evidence, the step from a FAIL to an upstream report"
else bad "sideeye evidence is gone; a reader of this page cannot learn a FAIL renders as a report"; fi

# 11. The command that installs the agent skills (#716). Not one of run 1's seven: what an agent's
# operator needs from this page, with the installer's version pinned.
if grep -qE 'npx skills@[0-9]+\.[0-9]+\.[0-9]+ add yottayoshida/sideeye' "$R"; then ok "the agent skills' install command, its installer pinned"
else bad "the agent skills' install command is gone, or no longer pins the installer's version"; fi

if [ "$fails" -ne 0 ]; then
    echo "$fails check(s) failed on $R"
    exit 1
fi
echo "the README keeps the path to a first verdict, at $lines lines and $words words"
