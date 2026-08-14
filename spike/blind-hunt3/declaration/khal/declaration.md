# The khal declaration — campaign 3, Seal B (ADR 0012 via ADR 0015/0016)

Selected by the sealed predicate over the committed sweep manifest
(`select.sh` → khal; sweep record, ledger 2026-08-14). Everything below is
declared from permitted sources only — the target's own --help set, the
version-pinned official usage page (`transcripts/docs-usage.txt`), and one
normal (non-crash) run per candidate form — before any crash-world
exploration. No traces, no source, no bug tracker; ADR 0016's structural
rule holds from observation time onward: every native store (a vdir and its
event files) that a probe, a red fixture, or a green run lets the target
read is khal-written, empty, or absent, and the `.ics` INPUT files fed to
`import` are hand-authored well-formed iCalendar — the documented input
class.

**Disclosure duty, discharged here and in the campaign report** (carried
from the prior seals, candidates.md): khal shares the vdir/iCalendar
storage class with todoman, which this project has explored. Class-level
knowledge is declared, not denied (candidates.md's taint ledger); no
khal-specific internals were consulted.

**Entities.** An *event*: one `.ics` file in the configured calendar
directory (observed: imports name the file `<UID>.ics`, normal-runs §1),
matched through khal's own `search` by its SUMMARY (observed line shape,
§4). Both invariants share this definition (ADR 0015 §2).

## Sources

| Transcript | What it is |
|------------|------------|
| `transcripts/help.txt` + `help-<cmd>.txt` ×12 | `khal --help` and every listed command's help, in the pinned container |
| `transcripts/docs-usage.txt` | khal.readthedocs.io/en/**v0.14.0**/usage.html, tags stripped (khal ships no man pages in the image; 586 lines) |
| `transcripts/normal-runs.txt` | one normal run per candidate form + determinism and interactivity probes (`normal-runs.sh`) |
| `transcripts/sources-provenance.txt` | package identity (khal 0.14.0), binary resolution, per-transcript line counts |

## The operation inventory

khal(1)-equivalent surface: twelve commands (help.txt). Exclusions use only
the sealed vocabulary (`interactive` / `network` / `destructive-by-design` /
`not-stateful`), with `interactive` in ADR 0012's channel sense stated once:
a form whose only documented input channel is a terminal or stdin, which the
exploration engine never supplies.

**Declared — three forms, all reaching the store through documented
non-interactive argv:**

| Form | Exercised argv shape | Forms not exercised |
|------|----------------------|---------------------|
| import (fresh UID) | `import --batch -a main <sealed .ics>` — the documented no-confirmation flag; UID not present in the vdir | `--random-uid`; stdin input (default when no ICS argument — the engine gives the child no stdin); the ask-first form without `--batch` (interactive: observed prompt + abort on EOF, §6) |
| import-update (same UID) | same argv, `<sealed v2 .ics>` whose UID already exists — docs: "--batch ... always update (i.e. overwriting)" | as above |
| new | `new -a main 01.09.2026 10:00 01.09.2026 11:00 TeamMeeting` (the sealed sweep row's shape) | `-i/--interactive`; repeat/until/location/categories/alarms/url/json options; keyword dates; timezone argument |

**Excluded forms:**

| Form | Verdict | Evidence |
|------|---------|----------|
| `interactive` (ikhal) | `interactive` | docs-usage: the TUI, keyboard-driven; deletion applies "when khal exits". Without a terminal: urwid PermissionError, exit 1 (§6) |
| `edit` | `interactive` | docs-usage: "an interactive command for editing and deleting events"; observed: prompts `Edit? [n]o [q]uit … [D]elete`, aborts on EOF, exit 1 (§6) |
| `configure` | `interactive` | observed: prompts for date ordering, aborts on EOF, exit 1 (§6); docs-usage: "will refuse to run if there already is a configuration file" |
| `at`, `calendar`, `list`, `search`, `printcalendars`, `printformats`, `printics` | `not-stateful` | documented printers (docs-usage). Observed honestly: over an EXISTING vdir they change no byte (§4, tree-level cmp); but `list` **created a missing configured vdir** (§5) — a directory-level write. The checker therefore queries only vdirs whose files its file legs have already required to exist |

`-c/-a/-d/-v/-l/--color/--format` are modifiers, not operations. No abookrc
equivalent is consulted beyond the sealed config format (khal.conf, sealed
at Seal A; the same shape as campaign 1's consultation recorded).

## The recovery-path rule (ADR 0015 §2): vacuous, and here is the enumeration that says so

The rule requires enumerating **every recovery, undo, or repair command form
the documentation names**. The enumeration base is the full help set (the
twelve command helps) and the version-pinned usage page — the widest
documentation this campaign may read. It finds **none**: no command and no
option is documented as recovery, undo, restore, rollback, backup or repair,
and a recovery-vocabulary grep over the whole usage transcript returns zero
hits (consultation ledger entry). `edit`'s delete and ikhal's
delete-on-exit are destructive editing, not recovery; `configure` writes an
initial config and refuses when one exists. Per clause (4) the declaration
states this explicitly and the rule discharges vacuously. Consequence,
stated rather than implied: a crash-damaged khal vdir has **no documented
in-tool recovery path** — whatever the exploration finds, "run the
documented recovery command" is not an available answer for this target.

## Determinism — one live search, two pre-registered refusal expectations

- **import (fresh UID) is byte-deterministic** in observation: two fresh
  imports of the same fixed-UID .ics produce tree-identical vdirs, one file
  named `<UID>.ics`, khal's own serialization preserving the input's fixed
  DTSTAMP (§1). No refusal is pre-registered; this is the live search.
- **import-update carries a pre-registered refusal expectation.** The
  same-UID `--batch` update, run NORMALLY, rewrote `<UID>.ics` and left
  extra files with random suffixes in the vdir, and the leftover names
  differ across runs (§2, measured in two independent vdirs). A
  byte-reproducible baseline is therefore not expected to exist; if the
  recording refuses, the refusal is the campaign's recorded result (#84),
  not a surprise. The leftover-file observation itself is a normal-run
  fact and is quoted here so nobody later mistakes it for a crash finding.
- **new carries a pre-registered refusal expectation** (carried from
  candidates.md and now measured precisely): it mints a random UID that is
  also the filename, and stamps DTSTAMP with the current time — two fresh
  runs differ in both name and bytes (§3).

**Severity, pre-registered as in the prior campaigns: loss outranks
duplication.**

## The invariants

Sources are tagged `doc` (a sentence in a sealed transcript) or
`observed-normal` (a normal-run observation in `normal-runs.txt`). The
conserved bystander is the event `GraceStandup` (UID
`grace-fixed-uid-001`); golden event files are committed fixtures written
by khal itself (`ops/make-goldens.sh`, resting on §1's byte-determinism).
Checker queries run with a fresh scratch HOME per invocation, so khal's
ambient cache (observed under `$HOME/.cache/khal/`, outside the state
root, §4) is rebuilt cache-cold from the vdir every time.

- **I-C — conservation (byte form).** The bystander event file
  `cal/grace-fixed-uid-001.ics` is byte-identical to its committed golden
  in every crash world. source: doc — the operations name their subject
  (`import ... ICSFILE` keyed by UID; `new` creates); nothing documents a
  write to an unrelated event's file. Missing file fails closed.
- **I-Q — bystander liveness through the target's own search.**
  `search GraceStandup` exits 0 **and** its output holds exactly one line
  anchored at line start as `02.09. 10:00-02.09. 11:00 GraceStandup` and
  nothing after the summary on that line (the observed match shape, §4;
  khal exits 0 even on no match — §4's miss probe — so the exit code alone
  certifies nothing and the anchored line carries the invariant). source:
  doc for search's meaning, observed-normal for the line shape and codes.
- **I-W — queries write nothing into an existing vdir.** The checker
  snapshots the whole vdir before its query legs and requires byte-tree
  equality after (diff -r). source: observed-normal (§4) — and this is a
  real invariant, not bookkeeping: a query that "cleans" or rewrites what
  it reads after a crash would violate it. The checker only ever queries a
  vdir whose bystander file its file legs already required to exist, so
  the observed create-missing-vdir behavior (§5) stays out of reach.
- **I-T — subject-query totality** (import and import-update). After a
  crash the subject's file may be absent, partial, or accompanied by
  leftover temp files; the declared property is the interface, not the
  shape: `search AdaMeeting` (the subject's summary prefix) terminates
  within the timeout and exits — a hang is the violation; no exit-code set
  is claimed (only 0 was ever observed, and observed-normal cannot ground
  a wider set). Its byte-neutrality is covered by I-W's snapshot.

What is deliberately **not** an invariant: the subject file's shape or
completeness after a crash (no atomicity promise exists in any sealed
transcript), the leftover temp files' presence or absence (observed even in
normal runs for the update path), and khal's ambient cache (outside the
state root; rebuilt cache-cold by the checker).

## Per-operation declaration

State roots: `/tmp/blind3/hunt/<op>/state`, per-op, fresh per container;
the configured calendar is `state/cal` (each op's sealed conf names it).
All argv frozen in the tomls; setups cp committed khal-written goldens.

| Op | Setup (pre-state in `cal/`) | Operation writes | Invariants checked |
|----|------------------------------|------------------|--------------------|
| import | golden-grace event file | `cal/ada-fixed-uid-001.ics` (new) | I-C, I-Q, I-W, I-T |
| import-update | golden-grace + golden-ada event files | `cal/ada-fixed-uid-001.ics` (rewrite) + observed leftover temp files | I-C, I-Q, I-W, I-T |
| new | golden-grace event file | one random-UID-named .ics | I-C, I-Q, I-W |

`expected_status` provenance: all three shapes exited 0 in normal runs
(§1, §2, §3) — the value "0" in all three tomls, verbatim.

## What this declaration does not check

- The TUI, `edit`, `configure`, the ask-first and stdin import forms, and
  every unexercised option combination (inventory above).
- The subject file's post-crash shape, the update path's leftover temp
  files, and the ambient cache.
- Default-path anything: every declared form names its config; HOME points
  at scratch throughout; the sealed conf names the calendar inside the
  state root.
- Recoverability via any in-tool command — there is none to check.

## Running the exploration

`run.sh`, sealed beside this file, is invoked by the phase driver from the
Seal B commit in a clean tree; it records head, cleanliness, the engine's
version string, and the SHA-256 of the engine and shim (R3 leg), requires
each op's report to exist and parse (fail-closed, per-op rows in the
manifest), and runs the three ops through their sealed tomls inside the
pinned container.
