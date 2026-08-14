# The khard declaration — campaign 2, Seal B (ADR 0012 via ADR 0015)

This directory is campaign 2's declaration, frozen before the first crash
measurement of its selected target: **khard 0.21.0**, picked by the sealed
predicate over the committed sweep manifest (`select.sh` on
`sweep-manifest.json` + `priority.txt`, recomputed by verify-seals B4; the
selection was announced by the phase driver on 2026-08-14, sweep verdicts
khard 0 / abook 0 / khal 0 / hledger 2). Everything here was written from the
permitted sources only — `khard --help` and per-subcommand help, the project's
own documentation (the three man pages, the command-line page, the scripting
page, all for v0.21.0), the vCard format's public specification (RFC 6350,
via ADR 0012's normative-format carve-out), and observed *normal* (non-crash)
behavior — each consultation itemized in the campaign ledger and reproduced
under `transcripts/`. No trace of khard, no crash experiment, no
write-ordering inspection, no source reading, no bug tracker. After this seal
merges, editing any invariant, checker, setup, config or toml here marks the
declaration sighted (ADR 0012 breach handling).

## Sources

| Transcript | What it is |
|------------|------------|
| `transcripts/help.txt` | `khard --version` + `khard --help` — the 16-subcommand inventory |
| `transcripts/help-subcommands.txt` | per-subcommand `--help` (with the sealed sweep config, which the help machinery requires) |
| `transcripts/man-khard.txt` | khard(1) |
| `transcripts/man-khard-subcommands.txt` | khard-subcommands(1) — the per-command reference the inventory below cites |
| `transcripts/man-khard.conf.txt` | khard.conf(5) — config syntax; the one-VCARD-per-`.vcf` sentence the carve-out rests on |
| `transcripts/docs-commandline.txt` | the docs' command-line page |
| `transcripts/docs-scripting.txt` | the docs' scripting page |
| `transcripts/normal-runs.sh` / `normal-runs.txt` | the observation script and its output: one normal run per declared form, the determinism measurements, and the interactivity probes |

## The operation inventory

`khard --help` lists sixteen subcommands. The unit is the subcommand; each
declared one names its exercised form; exclusions use only the sealed
vocabulary (`interactive` / `network` / `destructive-by-design` /
`not-stateful`), with the evidence named.

**Declared — four forms:**

| Subcommand | Exercised form | Forms not exercised |
|------------|----------------|---------------------|
| new (add) | `new -a main -i ada.yaml` (template file input — the engine gives the child no stdin) | stdin input, `--open-editor`, `--vcard-version` |
| remove (delete, del, rm) | `remove --force Ada` (the documented no-interaction flag) | interactive confirmation form |
| move (mv) | `move -a main -A second Ada` | — |
| copy (cp) | `copy -a main -A second Ada` | — |

**Excluded subcommands:**

| Subcommand | Verdict | Evidence |
|------------|---------|----------|
| edit (modify, ed) | `interactive` | prints the proposed modification, then waits for confirmation even with `-i` and no stdin (observed: 10s timeout, normal-runs §6) |
| add-email | `interactive` | its `Select? yes/[no]:` prompt repeats unbounded on stdin EOF (observed: ~200MB of prompt in 5s, normal-runs §7) |
| merge | `interactive` | khard.conf(5): `merge_editor` is "a command used to merge two cards **interactively**"; without one the command errors (normal-runs §8) |
| list, show, template, birthdays, email, phone, postaddress, addressbooks, filename | `not-stateful` | each is documented as a listing/printing command (khard-subcommands(1)); `template` prints to stdout |

All four declared forms exited 0 in normal runs (`transcripts/normal-runs.txt`),
the provenance for `expected_status = "0"` in every toml.

## The recovery-path rule (ADR 0015 §2): vacuous, and here is the enumeration that says so

The rule requires enumerating **every recovery, undo, or repair command form
the documentation names**. The enumeration over the sealed transcripts —
khard(1), khard-subcommands(1) (all sixteen subcommands and their full
descriptions), khard.conf(5), the command-line page and the scripting page —
finds **none**: no subcommand and no config option is documented as recovery,
undo, restore, rollback, backup or repair, and the words themselves do not
occur in a command sense anywhere in those pages. Per the rule's clause (4),
the declaration states this explicitly and the rule discharges vacuously.
Consequence, stated rather than implied: a crash-damaged khard store has **no
documented in-tool recovery path at all** — whatever the exploration finds,
"run the documented recovery command" is not an available answer for this
target, and the checker's I-B leg from campaign 1 has no khard analogue.

## Determinism, and two pre-registered refusal expectations

Measured in normal runs (§2, §5): `new` mints a **random UID** that becomes
both the filename and a `UID:` line, plus a second-precision `REV:` timestamp;
`copy` gives the copy a **new** random UID and REV. khard.conf(5) offers no
option to fix either (the config reference is sealed in full; its four
sections contain no filename or UID setting). Sideeye's un-killed baseline
world must reproduce the recorded final state byte-for-byte, so:

- **`new` and `copy` are declared with a refusal expectation**: the baseline
  will very likely differ (fresh UID/REV) and the engine should refuse with
  `baseline_violates_invariant` — the watson shape. If it does, that is
  recorded #84 data, pre-registered here, not a campaign failure. They are
  declared anyway: refusing honestly is a verdict, and the declaration cost
  is two small files.
- **`remove --force` and `move` are the live searches.** Measured: two
  identical stores end byte-identical after `remove` (§3), and `move`
  preserves both filename and bytes across addressbooks (§4). Their baselines
  should reproduce; `move` is the cross-file window (one contact, two
  directories) and `remove` the destructive one.

Setup randomness is harmless: the baseline replays the operation over the
recorded pre-state, not over a fresh setup — the campaign-1 revert precedent
(its backup store carried second-precision times from setup and the baseline
held).

## The invariants

Provenance vocabulary per ADR 0012: `source: doc <cite>` is a documented
promise; `source: observed-normal <transcript §>` is behavior a normal run
showed. The checker (`ops/check.sh`) instantiates the sealed wrapper
template; file-level checks use the carve-out (khard.conf(5): "khard expects
the vCard files to hold only one VCARD record each and end in a .vcf
extension"; RFC 6350 for the vCard structure).

- **I-Q — the query survives.** After a crash and no repair, `khard list`
  exits 0 and shows the conserved bystander. Every declared post-state keeps
  at least one contact, because an empty addressbook makes `list` exit 1
  (`Found no contacts` — observed §9, which is why the bystander exists).
  `source: doc` — khard-subcommands(1) list; shape `observed-normal` §9.
- **I-C — conservation of the bystander.** Grace Hopper, whom no declared
  operation's documentation licenses to touch, has exactly one vCard across
  the whole store in every crash world.
  `source: doc` — each subcommand's documented effect names only its subject;
  khard.conf(5) one-VCARD-per-file.
- **Per-subject invariants.** `new`: at most one Ada (a crashed create may
  leave the payload present or absent, never duplicated). `remove`: at most
  one Ada (present or removed, never duplicated). `move`: **exactly one Ada
  across both addressbooks** — never zero (lost), never two (duplicated); the
  cross-file window. `copy`: the source Ada stays in main; at most one copy
  in second.
  `source: doc` — the one-line synopses of new/remove/move/copy in
  khard-subcommands(1).
- **I-F — store shape.** Every `.vcf` present is a single complete vCard:
  first line `BEGIN:VCARD`, exactly one `BEGIN:VCARD`, an `END:VCARD`, and
  the mandatory `FN` property.
  `source: doc` — khard.conf(5); RFC 6350 §6.1.1/6.1.2 (delimiters), §6.2.1
  (FN is REQUIRED).
- **I-M — claimed durability** (marker, L1; all four). Markers are the
  observed past-tense success lines: `Creation successful` /
  `deleted successfully` / `Moved contact` / `Copied contact`.
  `source: observed-normal` §1, §3, §4, §5.
- **I-B — recovery:** vacuous; see the enumeration above.

**Severity, pre-registered** (a finding cannot be inflated after the fact):
loss (a contact in neither addressbook, or the bystander gone) is data
destruction — the severe direction. Duplication is moderate. I-Q / I-F
violations are store-integrity findings whose weight depends on what recovers
them — and this target documents no recovery path, which the report must
weigh honestly in both directions (worse: nothing to run; also less: nothing
to misfire).

## Per-operation declaration

| op | setup (`ops/setup.sh`) | operation | conserved | subject invariant | marker |
|----|------------------------|-----------|-----------|-------------------|--------|
| new | new Grace | `new -a main -i ada.yaml` | Grace ×1 | Ada ≤ 1 | `Creation successful` |
| remove | new Ada; new Grace | `remove --force Ada` | Grace ×1 | Ada ≤ 1 | `deleted successfully` |
| move | new Ada; new Grace | `move -a main -A second Ada` | Grace ×1 | **Ada = 1 across both books** | `Moved contact` |
| copy | new Ada; new Grace | `copy -a main -A second Ada` | Grace ×1 | Ada(main) = 1, Ada(second) ≤ 1 | `Copied contact` |

Conservation greps the files, not the listing (the carve-out): filenames are
random UIDs, so the checker counts `FN:` matches across `main/*.vcf` and
`second/*.vcf` rather than trusting names — and `khard list` is kept as the
liveness query only.

## What this declaration does not check

- **The subject's payload on `new`/`copy`** — present, absent or torn is not
  judged beyond "not duplicated"; only bystanders are conserved (campaign-1
  precedent).
- **Recovery after a crash** — there is nothing documented to run; stated
  above as a vacuous discharge, not silently skipped.
- **The unexercised forms** named in the inventory.
- **`sideeye preflight` was not run on these defines.** The sweep's single
  sealed run remains the only sideeye↔khard contact before Seal B; the
  declared operations beyond the swept shape (`new`) may be refused at
  exploration time, and two refusals are expected and pre-registered above.
  No invocation here was tuned against acceptance.

## Running the exploration

`run.sh` (sealed with this declaration) explores the four operations from the
Seal B merge commit in a clean tree, inside the pinned container, via
`spike/campaign-driver.sh explore` — which supplies HEAD/CLEAN/OUT and the
engine paths, refuses a reused output directory, and whose R3 audit requires
this runner's recorded engine/shim SHA-256 to equal the sweep manifest's.
Saved cases pin absolute `/tmp/blind2/hunt/<op>/...` paths, which resolve in
the image by construction.
