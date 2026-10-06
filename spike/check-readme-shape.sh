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
# 1.19 times the size of this one, which is a reason the re-run criterion 6 owes matters, not a
# substitute for it. Each check below is one of those seven, pinned by a
# sentence that carries its meaning rather than by a flag name a table could list without
# explaining — `--allow-unverified` alone in a flag list would pass a name check and tell
# the reader nothing about when it is needed.
#
# The size bound is the other half. The page had grown to 33 KB by writing each
# decision's record into it — issue numbers, ADR numbers, the reason behind each refusal —
# and those have homes of their own (DESIGN.md, docs/, docs/adr/). The bound is a sum of what
# the page must carry plus a fixed slack, not a target picked first: 8970 + 590 = 9560.
# The sum was corrected twice, upward, during the change that introduced this check, and both
# corrections were elements it had never counted rather than drafts that would not fit. First
# the 382-byte clause naming the one exception to "never a silent PASS", which an owner ruling
# (ADR 0032) requires in the sentence that makes the promise. Then the 284 bytes that let a
# reader start from the release artifact: the onboarding box holds README.md and a tarball and
# nothing else, network-off, so a page that sends the untar line to another file leaves the
# only artifact in the box unusable — which is what check 8 below now holds. A third, after the
# check shipped and for the same reason as the first: the 336-byte sentence that extends "a checker
# that cannot fail makes the run UNKNOWN" to an exploration in which no world could have failed,
# which an owner ruling (ADR 0091) puts beside the promise it extends rather than in another file.
# A fourth, the same kind (#702, 2026-10-06): the brew formula serves macOS, and the page's only
# explore line named strace, which macOS refuses — the first command a macOS reader copied could
# not run. The macOS line and the words that say which line is which are 63 bytes net, after
# the `--oracle` bullet gave up the clause naming strace; the two bytes of slack the page had are
# left as they were. Not as a `# macOS` at the end of the line: zsh, macOS's shell, does not read
# `#` as a comment when typed, so a pasted line would hand `#` to sideeye as an argument.
# A fifth (#700, 2026-10-06): the toml example's `cwd` line, 81 bytes. Without it the example
# ran its commands in Sideeye's own directory, so a define copied from it and given a relative
# argument meant one file from the toml's directory and another from anywhere else.
# A sixth (#703, 2026-10-06): the 414-byte line under "What the target has to be" naming a
# framework Python's launcher on macOS, the first target most macOS readers try, which the
# refusal now names a way past; a limit the page lists is the page's to state, and a way past
# it is part of the limit.
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

bytes=$(wc -c < "$R" | tr -d ' ')
lines=$(wc -l < "$R" | tr -d ' ')
if [ "$bytes" -le 9560 ]; then ok "size: $bytes bytes, at most 9560"; else bad "size: $bytes bytes, over 9560"; fi
if [ "$lines" -le 120 ]; then ok "length: $lines lines, at most 120"; else bad "length: $lines lines, over 120"; fi
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

if [ "$fails" -ne 0 ]; then
    echo "$fails check(s) failed on $R"
    exit 1
fi
echo "the README keeps the path to a first verdict, at $bytes bytes"
