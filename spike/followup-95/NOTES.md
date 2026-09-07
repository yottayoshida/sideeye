# followup-95 — hnb, re-posed under the argv form

**What this is.** The #84 sweep's hnb trial refused: its documented invocation
carries a space inside one argument (`-e "add second"`), the space-split
operation contract could not spell it, and the `op.sh` wrapper fallback refused
(`spike/unknown-rate/defines-b/hnb/`, the B-group table in
`docs/unknown-rate.md`). ADR 0019's argv form exists for exactly that
argument. This follow-up re-poses the same question with the same target,
same seeded state and same operation — spelled as argv — and keeps the
refused spelling beside it as the control.

**Corrected 2026-09-07:** the paragraph above said the wrapper was refused for
being a zero-prior-op exec chain. It was not. A wrapper of that shape naming an
absolute path reaches a verdict; hnb's names `hnb` for `PATH` to resolve, and the
shell execs once per entry while the engine counted the failed attempts as image
changes (ADR 0018's amendment). The control refused as recorded — what is
corrected is why, and that reason is now fixed in the engine rather than
documented as a property of the wrapper.

**This is not a corpus change.** The #84 corpus is frozen and its B-group
record stands as measured under the contract of its day; nothing here touches
`spike/unknown-rate/defines-b/` or the sweep artifacts. This directory is a
labeled follow-up in the `spike/followup-144/` shape.

**The pair, declared before running:**

- **Control (the refused spelling):** `op.sh` wrapping
  `exec hnb ... -e "add second" save` — expected to reproduce the sweep's
  refusal: UNKNOWN, `child_process_detected`, the v10 broken-chain message.
  If the control does not refuse, the apparatus differs from the sweep's and
  the green side proves nothing.

  **This reading is retired as of 2026-09-07, and the sentence above is left
  standing because it is what was declared.** The engine stopped refusing this
  spelling: the refusal was it counting a shell's PATH lookup as several image
  changes, and the reader no longer does that (ADR 0018's amendment). **Measured
  the same day, not inferred**: `bgroup.sh hnb` under the engine at `4083db2`
  answers `UNKNOWN child_process_detected` over 0 crash points, and under the fix
  **FAIL, 1 violation over 3 crash points** with the oracle agreeing on 3
  operations — the same verdict and the same count `artifacts/report-argv.json`
  holds for the argv form. So the two spellings do answer one question, and a
  control that does not refuse now means the engine changed rather than that the
  apparatus differs — the opposite reading to the one declared. The re-measurement
  ran in a **rebuilt** `sideeye-ur-extra` (image id `9fec97c7`, not the sweep's
  `df66b6e1`), so it is the recipe's apparatus rather than the sweep's artifact,
  and its transcripts are not committed. `run.sh`'s control pin is retired with
  the same date and keeps the original assertion quoted beside it. What the
  argv side measured is unaffected: its counterexample rests on its own report,
  case and replay, none of which the control was holding up.
- **The argv form:** `operation = ["hnb", "<state>/notes.hnb", "-ui", "cli",
  "-e", "add second", "save"]` — the claim is a verdict with a real
  exploration behind it: **crash points > 0** (a PASS with zero explored
  worlds would satisfy "a verdict" vacuously and is counted as a miss), the
  strict oracle attached.

**What either outcome means.** A verdict on the argv side means the sweep's
hnb wall was the spelling and nothing else. A refusal on the argv side names
the second wall the spelling hid — also a result, recorded as measured.

**Apparatus.** Engine and shim from this branch's cross-build, run in the
image the #84 B-group sweep used (`sideeye-ur-extra`, hnb baked in — so the
control refuses on the same target build; the transcript records the hnb
version, which is this run's link to that image — the image id itself is not
in the transcript). `run.sh` is the whole recipe; `artifacts/` holds both
reports, the saved case and the transcript.

## Result (2026-08-16, hnb 1.9.18+ds1-3 — the version the sweep's image bakes in)

Both sides landed as declared. `artifacts/` holds the reports, the saved
case and the transcript; `run.sh`'s pins re-verify the control's refusal,
the explored verdict (crash points > 0), and on a FAIL the v3 array-carrying
case and its replay — the oracle line and the violation window below are the
report's and the transcript's own record, quoted, not re-derived.

- **Control (wrapper spelling): UNKNOWN, child_process_detected** — the
  sweep's refusal, reproduced with this branch's engine on the same hnb
  build the sweep measured. The wall is still there for the spelling that
  hit it.
- **argv form: FAIL — 1 violation over 3 crash points, strict oracle
  agreeing on all 3 counted operations** (121 syscall lines examined, 28 in
  scope). The engine's own headline prints "1 of 4 crash worlds" — its
  denominator counts the baseline world; the report's machine fields say
  violations 1, crash_points 3. The earliest violation is the familiar
  truncating-rewrite window: killed between `open(notes.hnb)` and
  `write(notes.hnb)`, the notes file holds neither the old nor the new
  content — the devtodo/calcurse class on a third target. The saved case
  (case_version 3, the operation as a JSON array) replays in a fresh work
  directory: `the case reproduced`, exit 1.

So the sweep's hnb wall was the spelling and only the spelling: the same
question, spelled inside the contract by the argv form, explores fully and
finds a real counterexample on the first try. Disposition of the finding:
recorded in-repo, deliberately unreported upstream (the target-selection
rule — hnb is a small, effectively dormant project; the devtodo call).
