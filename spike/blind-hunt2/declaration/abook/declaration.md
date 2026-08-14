# The abook declaration — campaign 2, Seal B (ADR 0012 via ADR 0015)

Selected by the sealed predicate over the committed sweep manifest with khard
burned (`select.sh` → abook; the burn is ledger entry 2026-08-14). Everything
below is declared from permitted sources only — the target's own --help and
--formats output, the abook(1) and abookrc(5) man pages shipped in the pinned
package, and one normal (non-crash) run per candidate form — before any
crash-world exploration. No traces, no source, no bug tracker, no damaged
store was ever given to the target (the khard burn's structural rule, applied
from observation time onward: every store a probe or a red fixture offers the
target is abook-written, empty, or absent).

**Entities.** An *entry*: a name with its email address, as one numbered `[N]`
section of the native store (observed shape, normal-runs §1) and as one line
of `--mutt-query` output (normal-runs §5). Both invariants below share this
definition (ADR 0015 §2).

## Sources

| Transcript | What it is |
|------------|------------|
| `transcripts/help.txt` | `abook --help` inside the pinned container |
| `transcripts/formats.txt` | `abook --formats` (the format lists, including entries the man page lacks) |
| `transcripts/man-abook.txt` | abook(1) from the pinned deb (0.6.1-2+b1 — the image strips /usr/share/man; `sources.sh` downloads the exact installed version, asserts it, and unpacks without installing) |
| `transcripts/man-abookrc.txt` | abookrc(5), same provenance |
| `transcripts/normal-runs.txt` | one normal run per candidate form + determinism and interactivity probes (`normal-runs.sh`) |

candidates.md pins abook as apt 0.6.1-2; the installed binary reports
0.6.1-2+b1 (the Debian binNMU of the same source version; package identity in
normal-runs §7 and the sources run).

## The operation inventory

abook(1) has no subcommands; the unit is the documented option form. The
whole CLI surface is seven forms; exclusions use only the sealed vocabulary
(`interactive` / `network` / `destructive-by-design` / `not-stateful`), with
the evidence named.

**Declared — three forms, all of them `--convert` (the only documented
non-interactive writer):**

| Form | Exercised argv shape | Forms not exercised |
|------|----------------------|---------------------|
| import (convert vcard→abook into a fresh outfile) | `--convert --informat vcard --infile <sealed .vcf> --outformat abook --outfile <state file>` | other informats (abook, ldif, mutt, pine, csv, allcsv, palmcsv); stdin infile (default — the engine gives the child no stdin) |
| export (convert abook→vcard beside the store) | `--convert --informat abook --infile <state store> --outformat vcard --outfile <state file>` | other outformats (ldif, mutt, muttq, html, pine, csv, allcsv, palmcsv, elm, text, wl, spruce, bsdcal, custom with `--outformatstr`); stdout outfile (default — not a state write) |
| import-refused (convert onto an EXISTING outfile) | same argv as import, outfile pre-existing; `expected_status = "1"` | — |

The refusal is documented behavior nowhere and observed behavior once:
normal-runs §4 shows `cannot write file`, exit 1, store byte-identical. It is
declared as an operation *because* v8's `expected_status` makes a refusing
run recordable, and an interrupted refusal is exactly where a "harmless"
path could still damage the store it refused to replace.

**Excluded forms:**

| Form | Verdict | Evidence |
|------|---------|----------|
| `abook` (bare, the ncurses program) | `interactive` | abook(1) "text-based address book program", "COMMANDS DURING USE Press '?'"; without a terminal: "Error opening terminal: unknown.", exit 1 (normal-runs §6) |
| `--add-email` | `interactive` | abook(1): "Read an e-mail message from stdin"; on stdin EOF prints "Valid sender address not found", exits 0, writes no datafile (normal-runs §6) |
| `--add-email-quiet` | `interactive` | same stdin dependency and same EOF observation (normal-runs §6) |
| `--mutt-query <string>` | `not-stateful` | abook(1): "Make a query for mutt (search the addressbook for <string>)" — the checker's query leg, not an operation; its exit codes are observed in normal-runs §5 |
| `--formats` | `not-stateful` | prints the format lists, exit 0 (transcripts/formats.txt) |
| `--help` | `not-stateful` | prints usage, exit 0 (transcripts/help.txt) |

`-C/--config` and `--datafile` are modifiers, not operations (abook(1) lists
them as options taking effect on whatever form follows). No abookrc is used:
abookrc(5) calls the file optional with documented defaults, and no declared
form reads the config-driven TUI behavior.

## The recovery-path rule (ADR 0015 §2): vacuous, and here is the enumeration that says so

The rule requires enumerating **every recovery, undo, or repair command form
the documentation names**. The enumeration over the sealed transcripts —
abook(1) whole (99 lines), abookrc(5) whole (260 lines), --help, --formats —
finds **none**: no option and no config variable is documented as recovery,
undo, restore, rollback, backup or repair, and none of those words occurs in
a command sense in any transcript (`autosave` in abookrc(5) is a TUI
exit-time save toggle, not a recovery path). Per clause (4) the declaration
states this explicitly and the rule discharges vacuously. Consequence,
stated rather than implied: a crash-damaged abook store has **no documented
in-tool recovery path** — and the observed refusal to write onto an existing
outfile (normal-runs §4) means even re-running the import is documented-
observed to refuse rather than repair. Whatever the exploration finds, "run
the documented recovery command" is not an available answer for this target.

## Determinism — and why no refusal is pre-registered

Both writers are byte-deterministic in observation: the same vcard→abook
convert twice gives byte-identical stores, and the same abook→vcard export
twice gives byte-identical files (normal-runs §2, §3). The native store
carries no timestamp and no random identifier (observed store bytes,
normal-runs §1: a fixed comment, a `[format]` block naming program and
version, numbered sections). The khard/watson shape — random identifiers
defeating the byte-reproducible baseline — has no observed analogue here,
so this declaration pre-registers **no** refusal expectation. If recording
refuses anyway, that refusal is the recorded result (#84), not a surprise
this paragraph absorbed in advance.

**Severity, pre-registered as in the khard round: loss outranks duplication.**

## The invariants

Sources are tagged `doc` (a sentence in a sealed transcript of --help or a
man page) or `observed-normal` (a normal-run observation in
`normal-runs.txt`). The conserved bystander is the entry
`Grace Hopper <grace@example.com>`; golden stores are committed fixtures
written by abook itself (`ops/make-goldens.sh`, byte-determinism per
normal-runs §2 making "the bytes abook writes" a stable fixture).

- **I-C — conservation (byte form).** Every store the operation does not
  name as its outfile is byte-identical to its committed golden in every
  crash world. source: doc — abook(1) `--convert` "Converts <inputfile> in
  <inputformat> to <outputfile>": the form names one input and one output;
  nothing else has a documented write path. For import that store is the
  bystander book `keep/addressbook`; for export it is the source store
  itself (the cross-file window: a reader must not scribble what it reads);
  for import-refused it is the pre-existing outfile (observed refusing
  byte-identically in the normal run, §4).
- **I-Q — bystander liveness through the query.** `--datafile <store>
  --mutt-query grace@example.com` exits 0 and its output holds **exactly
  one** match line, anchored at the line start as
  `grace@example.com<TAB>Grace Hopper<TAB>` (the observed match shape,
  normal-runs §5 — email first, a tab, the name, a tab; anchoring the full
  email and full name with both separators is the khard-R1 lesson against
  prefix tolerance). The query leg runs **after** every file leg and leaves
  the store's bytes unchanged (snapshot-compare inside the checker). source:
  doc for the query's meaning (abook(1) "search the addressbook"), observed-
  normal for exit codes and line shape.
- **I-T — query totality on the import outfile** (import only). A crash may
  leave the outfile absent or partial; the declared property is not shape
  but the tool's own interface: `--mutt-query ada@example.com` against the
  outfile terminates within the timeout with exit 0 or 1 — the two
  documented-observed codes (match; "Not found"; "Cannot open database",
  normal-runs §5) — and leaves the outfile's bytes unchanged. An exit
  outside {0,1}, a hang, or a byte change is the violation. source:
  observed-normal.

What is deliberately **not** an invariant: the import outfile's shape or
completeness (no atomicity promise exists in any sealed transcript), and the
export file's content (same reason). The operation's *effect* (Ada present
after a successful import) is the green side's business, not a crash-world
invariant.

## Per-operation declaration

State roots: `/tmp/blind2/hunt/<op>/state`, per-op, fresh per container.
All argv frozen in the tomls; setup shapes below are the committed
`ops/setup.sh` (fixtures cp'd from sealed goldens — every store abook-written
at fixture-generation time).

| Op | Setup (pre-state) | Operation writes | Invariants checked |
|----|-------------------|------------------|--------------------|
| import | `keep/addressbook` = golden-grace; `book/` empty | `book/addressbook` (new) | I-C(keep), I-Q(keep), I-T(book) |
| export | `book/addressbook` = golden-pair (Ada+Grace) | `book/export.vcf` (new) | I-C(book store), I-Q(book store) |
| import-refused | `book/addressbook` = golden-pair | nothing (expected_status "1", observed §4) | I-C(book store), I-Q(book store) |

`expected_status` provenance: import and export exited 0 in normal runs
(§1, §3); the refused shape exited 1 (§4). Those observations are the
`expected_status` values in the three tomls, verbatim.

## What this declaration does not check

- The TUI surface, `--add-email`, `--add-email-quiet` (excluded above), and
  every unexercised `--convert` format pair.
- The import outfile's shape or completeness in crash worlds (declared
  property: I-T only), and the export file's content.
- Default-path stores (`$HOME/.abook/…`): every declared form names its
  files explicitly; HOME points at scratch throughout.
- Recoverability via any in-tool command — there is none to check (the
  recovery-path rule discharges vacuously above).

## Running the exploration

`run.sh`, sealed beside this file, is invoked by the phase driver from the
Seal B commit in a clean tree (verify-seals R1 leg); it records head,
cleanliness, the engine's version string, and the SHA-256 of the engine and
shim that ran (R3 leg, ADR 0015 field contract) into the run manifest, and
runs the three ops through their sealed tomls inside the pinned container.
