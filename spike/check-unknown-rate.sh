#!/bin/sh
# The root is the argument, not acceptance.sh's /work default: run by hand, /work does not
# exist and every path in the check reads as missing.
set -u

ROOT=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
fails=0

# Drift gate for docs/unknown-rate.md: the results block must byte-equal a fresh
# recomputation from corpus.tsv + the committed sweep artifacts (count.py check also
# re-verifies every manifest define digest against the checkout, requires published
# table rows >= corpus rows so an empty table can never read as a measured zero, and
# holds every unknown_reason to report-schema.md's closed set). Before the sweep's
# artifacts exist it asserts the explicit not-yet-measured placeholder instead.
# The gate's own predicates are proven falsifiable on committed fixtures every run —
# a fixture for each predicate this check NAMES, not only the two accidents that
# motivated the gate. **Not a fixture per predicate** — that reading was here until
# #341 and it was false: on 2026-09-01 `count.py` held 78 `if` guards that reached a
# `die()`, and a sweep that day that rewrote each of their tests to `False` in turn and
# re-ran every input this check fed found **36 whose removal changed nothing here**. They
# clustered in `check` (15) and in the readers' shape checks — `read_generations` (3),
# `check_attribution` (3), `load_reports` (2), `split_revision` (2), `check_ledgers` (2),
# and one each in `read_corpus`, `_reject_duplicate_ids`, `read_manifest`,
# `enum_from_schema_doc`, `digest_for`, `read_ledger`, `parse_section`,
# `check_dispositions` and `read_lines`. Column counts, duplicate ids, file existence,
# and the published page's arithmetic: a different family from the ones below, and filed
# rather than left implied — the same disclosure the distinctness gate makes about the
# reasons it does not credit.
#
# **How that 36 was counted, and why two earlier counts came out lower.** The candidates
# are every `if` whose body reaches a `die()`, found by walking the parse tree rather
# than by reading nearby lines; each test was rewritten to `False` in a copy and the
# whole of this check re-run — the live root, `good`, `setup-error-present`, and the 37
# tampered fixtures committed then, against their expected messages. A predicate was
# undetected when all 40 verdicts were unchanged. The two earlier passes found candidates by text proximity —
# a `die` within three lines of its `if` — and got 32, then 33 once the sites that
# heuristic had skipped were swept by hand; the published block's duplicate-slice
# refusal, whose `if` is separated from its `die` by a comment block, is the one it
# could not see. **The figure was complete for the file as it stood that day**: `count.py`
# contained no `assert` and no `raise`, and every one of its 71 `die()` calls sat inside
# an `if`, so there was no fourth way to guard one and nothing fell outside the candidate
# set. The sweep has not been re-run since, so the 36 says nothing about guards added
# after it. Measured again on 2026-09-16 for #598, by walking the parse tree: 85 `die()`
# calls, none outside an `if`, still no `assert` and no `raise` — 75 before #598's ten.
#
# The fixtures this check does name:
# fixtures/good must pass; tampered-verdict (report verdict flipped, docs stale),
# tampered-manifest (a row deleted), tampered-define (define bytes edited after the
# hash), tampered-reason (an unknown_reason outside the documented closed set) and
# predata-no-placeholder (no artifacts and no placeholder line) must all fail — the
# seen-red-once, kept red forever. #239 added seven more, for the generation model
# and the three cohort ledgers: gen-unstarted-with-manifest (a measured generation
# recorded as unstarted), gen-complete-no-manifest (the reverse), ledger-missing (a
# committed cohort define in none of the three ledgers), ledger-overlap (one define
# claimed by two), ledger-successor (a supersession row whose replacement is in no
# corpus), ledger-unrelated-successor (a replacement that is a different target) and
# outcome-new-this-sweep (an already-triaged tool parked as untriaged).
# #347 adds six more, for the two sides of the page's SETUP_ERROR rule and for the
# shape of the ledger that records them: setup-error-unwaived (a SETUP_ERROR nobody
# waived — the generation is marked complete and the rate publishes over what
# remains), setup-error-orphan-waiver (a waiver whose trial is not a SETUP_ERROR,
# which is what a waiver becomes once the apparatus it excused is repaired), and
# setup-error-empty-reason / setup-error-piped-reason / setup-error-duplicate-waiver
# / setup-error-marker-reason for read_exclusions' own four rules. Those four refuse
# inside the reader, so they fire in `emit` as well as `check` — that is the
# fail-closed direction, and it is why the message each carries names the ledger
# rather than whatever downstream thing would have tripped over the bad row.
# Each of the six is red for its own predicate and green without it: the first three
# shape fixtures were written against `good`, waiving a trial that is not a
# SETUP_ERROR, so removing the rule under test left them red on the orphan message
# instead — right rc, right text, wrong reason. They waive a real SETUP_ERROR now,
# and their published blocks are what the guard-less emitter renders, because a
# fixture whose docs do not match that is caught by the byte-compare instead.
# marker-reason needs a generation covering B alone with no rated trial: that is the
# only shape where nothing the attribution checks read comes after a detail table,
# and it is the shape the page contemplates for a future B measurement.
# #348 adds four more, for the apparatus record a completed generation is swept
# under: apparatus-missing (no record at all), apparatus-digest-missing (one digest
# line instead of two), apparatus-head-empty (`head: ` with no value — what
# sweep.sh writes when `git rev-parse` fails, since nothing there checks its rc) and
# apparatus-image-unlisted (no image lines — what it writes when `docker images |
# grep` returns nothing). The first three read only the file; the last is the one
# predicate that holds the record against the generation's own manifest.
# **apparatus-missing's red-once is defined differently from every other fixture
# here.** Removing its guard does not turn the fixture green: the read that follows
# raises instead, so what the removal changes is the KIND of red — a refusal with a
# pinned message becomes a traceback, which this loop reports as "died, but not on
# its predicate". That difference is the measurement.
# Two apparatus checks were considered and left out, named here so the omission is
# not read as an oversight. **The banner line** is not checked: truncation eats from
# the end, so a record can lose its images, then its head, then its digests, but a
# banner-only loss cannot be produced that way — it takes a targeted edit, which is
# equally invisible to every other rule here (rewriting one character of a digest,
# say). The search behind that was one probe deep: no generation in the current
# corpus leaves the image predicate covering an empty set (non-wall rows are A 36/36,
# B 7/20, control 1/1). "No shape was found" rather than "no shape exists".
# **Whether `head:` names a commit in this history** is not checked either: it would
# catch a real accident (a sweep interrupted and rebased left a head: pointing at a
# commit no longer reachable), but count.py calls neither git nor subprocess today,
# and bringing a git dependency into a tool that runs in the sweep container is its
# own decision.
# #598 adds ten, for the class-exclusions.tsv criterion — each row rests on its
# target's own row in docs/target-classes.md, and nothing in the first table reaches
# the target — and for the page shape that criterion is read from.
# ledger-exclusion-unnamed (no row cites the define's cohort directory outside an HTML
# comment, where no reader sees it; the quote is a real refusal-table Class cell, so
# comparing the string alone would pass it),
# ledger-exclusion-stale-quote (the row that cites it was reworded under the quote —
# Bun's row on 2026-09-16), ledger-exclusion-supported (a first-table row cites the
# directory), ledger-exclusion-supported-by-tool (a first-table row names the same tool
# and cites no directory — how virtualenv, zstd and ansible-core crossed — spelled as a
# link, which the word reader has to see through),
# ledger-exclusion-class-supported (the quoted class is a first-table Class cell on
# another tool's row — ansible-core crossed under its own Class cell, and mlr shares
# cargo's), ledger-exclusion-no-classes-page (the page is absent),
# ledger-exclusion-first-table-gone (its heading renamed), ledger-exclusion-first-table-
# empty (the heading stands over no rows), ledger-exclusion-split-table (a blank line
# inside a Class table, where GitHub ends it) and ledger-exclusion-excess-cells (a row
# with more cells than its header — an unescaped `|` in a code span, which GitHub
# splits on and whose extra cells it drops; Bun's row lost its Recorded in cell that
# way). Each guard was rewritten to `False` in turn and the live root, `good` and all
# ten re-run: every rewrite changed its own fixture and nothing else — green for seven,
# and for unnamed, no-classes-page and first-table-gone the kind of red, the unnamed row
# then failing the quote comparison, the absent page a traceback, the missing heading
# the empty-table refusal. Two readers were reverted the same way: without removing
# comments before reading directories, unnamed turns green; with the Tool cell's first
# word taken by splitting on a space, supported-by-tool does.
# The first of #239's seven was itself red for the wrong reason when it was written —
# count.py read its reports before checking its status, so it died on a missing file
# — which is what this loop's message-matching exists to catch. **Predicates with no
# fixture, named so nobody reads this list as complete.** From #239: the generation
# group closed set, the since/group coverage rule, outcome-map's
# shape/uniqueness/enum, and the *disposition* conservation assert — an A-group FAIL
# whose tool carries a disposition the outcome table does not print, count.py's block
# headed `Conservation:`. That is NOT the attribution checks pinned below: those are a
# different predicate, and they are named attribution precisely so this sentence can
# tell the two apart. From the attribution work: the two post-byte-compare numerator
# bindings — the rate line's, and the outcome table's per-row comparison. Both read
# verdicts, so both would take `tampered-verdict`'s pinned message if they ran before
# the byte-compare; that is measured rather than reasoned, because the outcome one
# was written there first and did exactly that. No data-only fixture reaches either:
# one that perturbs the number dies earlier. Also the (B, judge) axis, which the
# funnel table cannot express because it
# has no judge column, so that family is measured by its denominator alone and the
# check says so in its own success line. From #444: emit's own marker count in the
# END direction — the begin direction has marker-emit-begin, but no committed cell
# can carry MARK_END past the read_exclusions reason guard into a block that
# otherwise passes, so that half of the emit-side assert stands unfixtured.
# Deleting any of these leaves this suite
# green, and that gap is filed rather than left implied. From #349: the refusal for a
# funnel wall row carrying a report hash. A wall runs no engine, `sweep.sh` writes `-`
# there, and no committed manifest has one (46 walked, zero hits) — the predicate exists
# for a manifest edited by hand, which is the threat the column is about, and a fixture
# for it would have to be a manifest nothing produces. Sunset: never fired by the
# v1.0 freeze -> removal list (same rule as check 11).
ur_fails=0
# Counted by the loop rather than written here: the sentence said "twelve" while the
# list below held twenty, because nothing recomputes a number kept in prose beside
# the thing it counts.
ur_red=0
ur_seen=
ur_blob=
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT"; then
    echo "     the live page/artifacts disagree with recomputation"
    ur_fails=$((ur_fails + 1))
fi
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/good" >/dev/null 2>&1; then
    echo "     fixture good failed — the gate cannot pass its own known-good input"
    ur_fails=$((ur_fails + 1))
fi
# A second green fixture, and the only place a SETUP_ERROR row exists at all: the
# live page has none and neither does `good`, so the rule that keeps such a row out
# of every denominator was reachable by nothing. Green here proves the exclusion
# holds; removing it from count.py turns THIS fixture red on the attribution row
# count while good and the live tree stay green (measured before shipping). It
# carries one SETUP_ERROR per published table shape — fx-toyE in the wide A-group
# table and fx-toyD in the B-group funnel table, whose excluded cell sits in a
# different column — because with only the A-group row the funnel half of that
# renderer was covered by reading the code and nothing else. Both are waived in
# exclusions.tsv, so this is also where a waived reason is proven to reach the
# published table rather than only to pass the ledger's own shape rules.
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/setup-error-present" >/dev/null 2>&1; then
    echo "     fixture setup-error-present failed — the SETUP_ERROR exclusion has no other reachable input"
    ur_fails=$((ur_fails + 1))
fi
# A third green fixture, and the only tree whose apparatus record carries a machine:
# line (#696, ADR 0104): g1 swept on x86_64 with an x86_64 asset pinned, a launcher-rc
# in every trial directory, and the heading naming the platform. Without it the rules
# that read the line are reached only by the red fixtures below, which a rule that
# refused every machine line would pass as well.
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/machine-x86-good" >/dev/null 2>&1; then
    echo "     fixture machine-x86-good failed — a generation measured on x86_64 cannot be published"
    ur_fails=$((ur_fails + 1))
fi
# A fourth: g2 re-measures B2 after g1, and the B2 authoring clock is printed under
# g1 only (#696 — g4 re-measures g3's B2 and authored nothing). The emit before #696
# printed it under both, and against this tree reads as drift.
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/b2-remeasured-clock-once" >/dev/null 2>&1; then
    echo "     fixture b2-remeasured-clock-once failed — the authoring clock is printed under a generation that re-measured B2"
    ur_fails=$((ur_fails + 1))
fi
# Each tampered fixture must die on ITS OWN predicate's message, not merely
# exit non-zero: a fixture that dies for an unrelated reason (a missing
# file, a parse error) is a hollow red — it proves nothing about the
# predicate it was built for, and an rc-only loop cannot tell the
# difference (R2 caught a mid-flight state where all five were red for the
# wrong reason).
for pair in \
    "tampered-verdict:differs from recomputation" \
    "tampered-manifest:against its expected" \
    "tampered-define:define digest mismatch" \
    "tampered-reason:not in the documented closed set" \
    "predata-no-placeholder:lacks the not-yet-measured placeholder" \
    "gen-unstarted-with-manifest:marked unstarted but" \
    "gen-complete-no-manifest:marked complete but has no manifest" \
    "ledger-missing:in no ledger" \
    "ledger-overlap:must be disjoint" \
    "ledger-successor:which is not a corpus define" \
    "ledger-unrelated-successor:which is a different target" \
    "ledger-exclusion-unnamed:names no row outside the first table" \
    "ledger-exclusion-stale-quote:quote the Class cell verbatim" \
    "ledger-exclusion-supported:a first-table row, names its directory" \
    "ledger-exclusion-supported-by-tool:name the same tool" \
    "ledger-exclusion-class-supported:which is also a Class cell of the first table" \
    "ledger-exclusion-no-classes-page:docs/target-classes.md is missing" \
    "ledger-exclusion-first-table-gone:'## Measured, with verdicts' headings, not 1" \
    "ledger-exclusion-first-table-empty:has no Class rows under" \
    "ledger-exclusion-split-table:a blank line splits the Class table" \
    "ledger-exclusion-excess-cells:cells where its table's header has" \
    "outcome-new-this-sweep:declaring an already-triaged tool untriaged" \
    "attribution-slice-denominator:a row reaches its slice exactly once" \
    "attribution-slice-numerator:in the published rows" \
    "attribution-family-missing:a slice family that loses a label" \
    "attribution-denominator-drift:the table and the measurement disagree" \
    "attribution-detail-row-missing:rated rows against" \
    "attribution-reason-table:the reason table is" \
    "attribution-reason-sum:the reason counts sum to" \
    "attribution-outcome-sum:a row leaves the ratio without leaving a trace" \
    "setup-error-unwaived:SETUP_ERROR with no row in exclusions.tsv" \
    "setup-error-orphan-waiver:a waiver outliving its trial excuses nothing" \
    "setup-error-empty-reason:is waived with no reason" \
    "setup-error-piped-reason:reason contains a pipe" \
    "setup-error-duplicate-waiver:exclusions.tsv lists 'fx-toyE' twice" \
    "setup-error-marker-reason:carries the results block's end marker" \
    "apparatus-missing:apparatus.txt is missing" \
    "apparatus-digest-missing:digest lines, not the engine's" \
    "apparatus-head-empty:no resolved head: line" \
    "apparatus-image-unlisted:the apparatus record does not" \
    "gen-group-unknown:is not one of A/B/B2/control" \
    "gen-covers-no-group:a row no generation covers" \
    "corpus-since-unknown:is not a generation" \
    "outcome-map-columns:outcome-map.tsv row does not have 3 columns" \
    "outcome-map-duplicate:outcome-map.tsv lists 'toyA' twice" \
    "outcome-map-disposition:is not one of reported-upstream/" \
    "outcome-conservation:carry a disposition the outcome table does not print" \
    "marker-second-end:docs/unknown-rate.md carries 2 end markers" \
    "marker-second-begin:docs/unknown-rate.md carries 2 begin markers" \
    "marker-inverted:end marker precedes its begin marker" \
    "marker-predata-second-end:docs/unknown-rate.md carries 3 end markers" \
    "marker-emit-begin:recomputation carries 2 begin markers" \
    "report-swapped:is not the one the sweep wrote" \
    "apparatus-engine-pin-missing:engine-pins.tsv pins v0.0.0-fixture but" \
    "legs-second-leg-unasked:a second leg was recorded without leg 1 asking" \
    "legs-second-leg-missing:no second leg was recorded" \
    "legs-final-not-last:is not the last leg's bytes" \
    "legs-sha-mismatch:hashes differently from legs.tsv" \
    "b2-corpus-unbound:corpus B2 rows differ from the committed b2-targets.txt" \
    "legs-columns:legs.tsv row does not have 6 columns" \
    "legs-report-missing:which is not in artifacts" \
    "legs-verdict-mismatch:legs.tsv says leg 2 is FAIL and its report says PASS" \
    "legs-reason-mismatch:reason is oracle_saw_phantom and its report says" \
    "legs-order:must list leg 1, optionally followed by leg 2" \
    "legs-mode-order:not wrappers then syscalls" \
    "legs-report-torn:leg 2: report-syscalls.json is not JSON" \
    "engine-pins-columns:engine-pins.tsv row does not have 4 columns" \
    "engine-pins-duplicate:engine-pins.tsv pins generation 'g1' twice" \
    "clock-columns:b2-clock.tsv row does not have 3 columns" \
    "b2-targets-missing:b2-targets.txt is missing" \
    "legs-missing-b2:a B2 trial with no legs.tsv" \
    "legs-report-schema:leg 1: report-wrappers.json is not a sideeye/report document" \
    "report-torn:fx-toyA: report.json is not JSON" \
    "clock-time-unparsable:has a time that is not YYYY-MM-DDTHH:MM:SSZ" \
    "clock-event-unknown:carries event 'gave_up', not one of" \
    "clock-duplicate:stamps 'toyE' final twice" \
    "machine-heading-missing:the published heading for it does not name the platform" \
    "machine-pin-mismatch:pins the aarch64 asset" \
    "machine-missing-x86-pin:has no machine: line, so it reads as aarch64" \
    "machine-unknown-name:does not name a host and a container machine" \
    "machine-two-lines:machine: lines, not one" \
    "machine-launcher-rc-missing:trial directories have no launcher-rc" \
    "machine-emulated:the trials were emulated"; do
    ur_red=$((ur_red + 1))
    bad=${pair%%:*}; want=${pair#*:}
    ur_seen="$ur_seen $bad"
    out=$(python3 "$ROOT/spike/unknown-rate/count.py" check \
          --root "$ROOT/spike/unknown-rate/fixtures/$bad" 2>&1)
    rc=$?
    ur_blob="$ur_blob
@@F@@
$bad
$want
$out
@@E@@"
    if [ "$rc" = 0 ]; then
        echo "     fixture $bad PASSED — the gate has gone blind to its own predicate"
        ur_fails=$((ur_fails + 1))
    elif ! printf '%s' "$out" | grep -qF "$want"; then
        echo "     fixture $bad died, but not on its predicate (wanted: $want)"
        printf '%s\n' "$out" | head -3 | sed 's/^/       /'
        ur_fails=$((ur_fails + 1))
    fi
done

# A committed tampered fixture that no row above names is a fixture nobody runs, and the
# loop cannot notice its own absence: `ur_red` is printed, never compared, so a list that
# loses rows still reports "ok". That is not hypothetical -- while writing #341 the seven
# new rows landed one line below the `; do` and became a command in the loop body, which
# `sh -n` accepts and `set -u` does not stop; the check printed `gate red on all 0
# tampered fixtures` and passed. Reconciling against the directory catches both that and
# a fixture added without a row. `good`, `setup-error-present`, `machine-x86-good` and
# `b2-remeasured-clock-once` are the four that are meant to pass, so they are the only
# names exempt.
ur_committed=0
for d in "$ROOT"/spike/unknown-rate/fixtures/*/; do
    name=${d%/}; name=${name##*/}
    case " good setup-error-present machine-x86-good b2-remeasured-clock-once " in *" $name "*) continue ;; esac
    ur_committed=$((ur_committed + 1))
    case " $ur_seen " in
        *" $name "*) ;;
        *) echo "     fixture $name is committed but no row above names it -- it is never run"
           ur_fails=$((ur_fails + 1)) ;;
    esac
done
# The other direction: a duplicated row runs a fixture twice and inflates the number this
# check prints. Comparing the two closes the loop on a count that was, until #341, only
# ever displayed.
if [ "$ur_red" != "$ur_committed" ]; then
    echo "     the list ran $ur_red fixtures against $ur_committed committed -- a row is duplicated"
    ur_fails=$((ur_fails + 1))
fi

# And a want must belong to exactly one fixture. The loop asserts that a fixture dies on a
# message containing its want; it does not assert the want could not have come from
# somewhere else, and a short one cannot. Three of the thirty-seven rows failed that when
# it was first measured (#341): `is not one of` also fits the generation table's group
# vocabulary and the ledger's "silence is not one of those", and a new row made a
# PRE-EXISTING pair ambiguous by producing the same "twice - the later row would win in
# silence" sentence from a different file. Without this, the sentence at the top of this
# check holds by the fixtures' luck rather than by the check. Cross-checked on the output
# the loop already captured, so no fixture is run twice.
ur_amb=$(printf '%s\n' "$ur_blob" | awk '
    $0 == "@@F@@" { getline cur; getline wv; n++; wn[n] = cur; wt[n] = wv; next }
    $0 == "@@E@@" { cur = ""; next }
    cur != ""     { out[cur] = out[cur] $0 "\n" }
    END {
        for (i = 1; i <= n; i++) {
            others = ""
            for (f in out)
                if (f != wn[i] && index(out[f], wt[i]) > 0) others = others " " f
            if (others != "")
                printf "     want for %s also matches%s - it does not name its own predicate\n", wn[i], others
        }
    }')
if [ -n "$ur_amb" ]; then
    printf '%s\n' "$ur_amb"
    ur_fails=$((ur_fails + $(printf '%s\n' "$ur_amb" | wc -l | tr -d ' ')))
fi
# The B2 selection chain (#619, ADR 0073): the committed target list is the keyed
# first-N derivation of the pool minus the exclusions, and every name the five
# machine-readable ledgers spell is excluded directly or through the alias table.
# A mode of its own rather than a branch of `check`, because the fixture trees
# above carry no B2 files and a fail-closed reader there would hollow out every
# red they exist to prove — the reason check-ledger-prose.sh is separate too. Its
# reds are proven by its own selftest on a scratch copy of the live tree: the
# baseline copy green, then one mutation per refusal the mode can raise (twenty-two:
# the derivation proven twice, the short-row refusal once per ledger read past
# column 0), each dying on its own message and the count of proofs asserted. The selftest's output is kept and printed on failure — a red
# whose `die()` sentence is thrown away says only that something failed.
if ! python3 "$ROOT/spike/unknown-rate/count.py" b2-selection --root "$ROOT"; then
    echo "     the committed B2 selection is not select-b2.sh's derivation, or a ledger name is not excluded"
    ur_fails=$((ur_fails + 1))
fi
b2_st=$(python3 "$ROOT/spike/unknown-rate/count.py" b2-selection --selftest --root "$ROOT" 2>&1)
b2_rc=$?
if [ "$b2_rc" != 0 ]; then
    echo "     b2-selection --selftest failed: a mutation the mode should refuse passed, or the baseline copy is red"
    printf '%s\n' "$b2_st" | grep -v '^count.py b2-selection: OK' | tail -3 | sed 's/^/       /'
    ur_fails=$((ur_fails + 1))
fi
# The second-leg trigger (#619): bgroup.sh runs `--observe syscalls` when leg 1's
# next_step opens with the `observe_syscalls` step's sentence, and count.py
# recomputes that decision from the same phrase. Both are copies of a string in
# src/contract.zig, and the two failure directions are not symmetric: a copy that
# drifts so the trigger never fires leaves every B2 verdict at the default mode
# with nothing said, while one that fires unasked is refused by count.py. This
# holds the three spellings to each other — the phrase count.py declares must be
# the opening of the `.observe_syscalls` arm and must appear verbatim in the
# launcher's `case`.
step=$(sed -n 's/^SYSCALLS_STEP = "\(.*\)"$/\1/p' "$ROOT/spike/unknown-rate/count.py")
if [ -z "$step" ]; then
    echo "     count.py declares no SYSCALLS_STEP — the second-leg rule has lost its phrase"
    ur_fails=$((ur_fails + 1))
else
    if ! grep -qF ".observe_syscalls => \"$step" "$ROOT/src/contract.zig"; then
        echo "     the second-leg trigger phrase is not how src/contract.zig opens the observe_syscalls step: '$step'"
        ur_fails=$((ur_fails + 1))
    fi
    if ! grep -qF "UNKNOWN:*\"$step\"*)" "$ROOT/spike/unknown-rate/launchers/bgroup.sh"; then
        echo "     bgroup.sh does not trigger its second leg on count.py's SYSCALLS_STEP phrase: '$step'"
        ur_fails=$((ur_fails + 1))
    fi
fi
if [ "$ur_fails" = "0" ]; then
    echo "ok   unknown-rate page in sync; gate red on all $ur_red tampered fixtures; B2 selection chain holds"
else
    echo "FAIL unknown-rate drift gate: $ur_fails problem(s)"
    fails=$((fails + 1))
fi

[ "$fails" = 0 ]
