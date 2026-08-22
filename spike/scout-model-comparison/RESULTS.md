# Scout model sensitivity — results (#221)

The design is `PROTOCOL.md` (filed verbatim as #221 before the arms ran).
Four fresh, context-free agents — Claude Fable 5 (control), Claude Opus 5,
Claude Sonnet 5, Claude Haiku 4.5 — each ran the identical single-pass scout
(steps 2–3 of the loop: read and propose; no defines, no execution, no
network, no access to this repository) over local checkouts of the assisted
five at the recorded versions (buku 4.7, calcurse 4.7.1, devtodo 0.1.20,
pass 1.7.4, stow 2.3.1). Their outputs are committed verbatim under
`arms/<model>/` — five `proposals-<target>.md` plus a mandatory
`DISCLOSURE.md` per arm; nothing was edited. Scoring key: the committed
2026-08-14 scout artifacts (`spike/assisted/*/proposals.md`) and the measured
outcomes (`spike/assisted/RESULTS.md`). Run date: 2026-08-22.

## Headline

**Opus 5 matched or exceeded the Fable control and the committed baseline;
Sonnet 5 is usable, with misses of the kind the downstream gates exist to
catch; Haiku 4.5 fell below the bar.** Owner ruling (2026-08-22): the scout
runs on a frontier-class model — Opus 5 or better; Sonnet 5 is the measured
floor. The requirement is stated in `docs/scouting.md`.

## P1 choices against the measured record

The record's strongest answers: calcurse `-P --purge` (the cohort's one
immediate FAIL, replay-confirmed), stow unfold (later reached a verified
counterexample), devtodo `--remove` / buku `--add` (deterministic picks that
dodge the targets' clock and randomness traps), pass same-`.gpg-id` `mv`
(the deterministic residue of a gpg-bound tool).

| target | fable | opus | sonnet | haiku |
|---|---|---|---|---|
| calcurse | import / `-F` write-back — same truncation mechanism as the FAIL | **`-P` with `apts` as bystander — the measured FAIL's exact shape, found independently** | import (3-file window); purge named in §2 but not proposed | `--save` — flag does not exist (verified against `src/args.c`'s option table) |
| buku | delete+compact two-row window | delete+compact, plus two windows the record does not have (below) | `--unlock` decrypt — sound analysis, but the record measured the passphrase channel as not reliably drivable | export (writes a new file, weak), `-e` mislabeled as encrypt |
| devtodo | backup-rotation contract | backup rotation / linked-DB interleave / default-truncate (the record's own P1 class) | silent-overwrite recovery finding (novel), but P1 argv is `-a` — the record's measured epoch-stamp trap | `--add` (the trap, uncalled), in-memory tree properties |
| pass | init rotation with refusal declared; deterministic `rm` as the recordable op | `mv -f` of a directory — the record's P1 one size up | git-enabled store as the fixture for P1/P2 (hidden wall, see below) | init reencrypt (refusal miscalled: `$RANDOM`, not gpg), interactive insert/edit |
| stow | unfold — the record's P1 | unfold — the record's P1, with a recovery-first checker | unfold — the record's P1 | plain first stow; "never mixed" invariant that stow does not promise |

## Determinism forecasts against the record

The sharpest discriminator. The record's measured traps: buku `--lock`
salt/IV from `os.urandom`; devtodo `--add`/`--done` stamping epoch seconds
(per-second flaky); pass gpg session keys; calcurse and stow deterministic.

- **fable: 5/5 correct**, each with file:line citations (buku urandom at
  `buku:220,225`; devtodo `time(0)` at `support.cc:677`; pass gpg + urandom;
  calcurse/stow deterministic with the right caveats).
- **opus: 5/5 correct**, plus hazards the record does not mention: the
  sqlite rollback-journal header (flagged as ~75% confidence, honestly),
  devtodo's `--purge` debug print to stdout, pass's `.git/index` embedding
  `st_ino`/`st_mtime` (not pinnable by clock control), `$RANDOM` temp names
  landing inside the store.
- **sonnet: 3 clean, 2 partial.** buku (split lock/unlock profile — the
  unlock-reads-salt-back observation is correct and sharp), calcurse, stow
  clean. devtodo: identified the epoch-stamp mechanism, then proposed `-a`
  as P1 anyway on an assumed clock pin. pass: called the gpg session-key
  refusal correctly, but built P1/P2 on a git-enabled store and flagged only
  commit timestamps as pinnable — not the `.git/index` inode problem.
- **haiku: 2 of 5, with three wrong calls.** Invented a "visited timestamp"
  determinism risk for buku (the schema at `buku:501-507` has no timestamp
  column — verified), missed devtodo's real epoch stamps, and attributed
  pass's nondeterminism to `$RANDOM` temp filenames while missing gpg
  ciphertext itself.

## Drivability

Six of haiku's fifteen argvs cannot run as written: a nonexistent
`calcurse --save`, a daemon wait (`-s periodic`), an interactive-UI
scenario, `pass insert` ("enter password twice"), `pass edit` (opens
`$EDITOR`), and a buku step annotated "via Python API". Sonnet has one
measured-undrivable P1 (buku `--unlock`'s `getpass` channel — the record
probed EOF-stdin behaviour and found it not reliably drivable). Opus
proposes only argv-drivable operations and declined the buku lock/unlock
window outright, for the same two reasons the 2026-08-14 scout excluded
it. Fable carries that window as a conditional P3 — refusal forecast
declared, to be skipped unless the engine grows urandom pinning and a
stdin channel; the passphrase channel that plan would need is the same one
the record measured as not reliably drivable, and the same one counted
against sonnet's P1 above. Fable's other proposals are argv-drivable.

## Static claims beyond the record (unverified by measurement)

Opus produced four findings the committed record does not contain. They are
static reading, not measurements — none has been probed or explored:

1. buku multi-index delete (`--delete 2 5`) commits per index with no
   enclosing transaction (CLI loop at `buku:5963-5974`; `delete_rec`
   defaults `delay_commit=False`) — a durable partial delete needing no
   crash inside sqlite.
2. buku import with one duplicate URL: `append_tag_at_index` defaults
   `delay_commit=False`, so the input file's content decides the
   transaction boundary of an otherwise-atomic import.
3. calcurse `-P --filter-completed` deletes every appointment (the
   appointment predicate has no completed term, so inversion drops them
   all) — a live footgun, filter semantics rather than crash consistency.
   Adjacent: the CLI purge/import paths bypass `io_save_cal`, so pre/post
   save hooks (including the shipped git-backup example) never run there.
4. pass on a git store cannot be byte-reproducible via clock pinning alone
   (`.git/index` embeds inode numbers).

Spot-check performed on the load-bearing citations before accepting any of
the tables above: six citations opened against the checkouts (buku range
loop `:1598-1605` with forced `delay_commit=True`; buku multi-index CLI
loop `:5960-5975`; calcurse purge save pair `args.c:905-907`; the
truncating `fopen(...,"w")` at `io.c:277`; devtodo `time(0)` at
`support.cc:676-678`; pass temp+`mv` idiom at `password-store.sh:134-138`)
— six of six matched. The other citations were not individually verified.

## Axis mapping against the frozen protocol

PROTOCOL.md froze five scoring axes. Their coverage here: axis 2 (the
cross-file transaction found) → the P1 table; axis 4 (determinism risk
called) → the forecasts section; axis 5 (where-from verifiable) → the
six-citation spot-check. Axes 1 (state root correct) and 3 (property is a
real contract) were not separately tabulated: axis 3's judgement is
embedded in the P1-table cells and the per-target notes, and axis 1 is not
scored in this record — the arm files carry each arm's own state-root
identification, and no row-by-row tabulation was made, so no per-arm claim
about it is asserted here.

## Timing and volume

Arms were spawned ≈12:11 JST; last-file mtimes (recorded from the working
tree before commit — git does not preserve mtimes, so a fresh clone will
not reproduce them): haiku 12:15:13, fable 12:26:38, sonnet 12:31:06 (one interruption
and resume in the middle), opus 12:34:33. Proposal volume: haiku 22,873
bytes, fable 33,728, sonnet 79,038, opus 95,191. Depth cost time; the
cheapest arm was also the wrong one.

## Validity caveats

- n=1 per model, one cohort, paper-only — no defines were written, nothing
  was explored. Proposal quality is scored against the record, not against
  fresh measurement.
- Conditions differ from the 2026-08-14 baseline (which had `--help` of the
  pinned builds, behaviour probes, and DeepWiki): the arms read source only.
  The controlled comparison is therefore arm-vs-arm; the committed record is
  the answer key, not a fifth arm.
- Contamination, measured before the run: the workspace memory index is
  injected into fresh subagents. Cohort-2/3 targets were excluded for that
  reason (their walls are in the index). Of the assisted five, the index
  leaks *existence of an upstream filing* for calcurse and stow (issue
  numbers only). All four arms disclosed the same leak verbatim and
  declared non-use — `arms/*/DISCLOSURE.md`.
- The grader is the orchestrating session: the same model family as the
  control arm, unblinded. Bias toward the control arm is possible; every
  judgement above is anchored to committed text a reader can check.
- devtodo is dormant by this repository's own selection rule (PROTOCOL.md
  hard gate). It appears here only as reuse of the frozen 2026-08-14 record
  for scoring — no new measured contact, nothing upstream. The fable arm
  flagged this unprompted in its disclosure.

## Implication for #118, recorded

`spike/assisted/RESULTS.md` recorded a failure-mode inversion: the metadata
gate was built against vacuous questions, and none appeared. That
observation is scout-tier-dependent. At the small tier they do appear — and
the metadata gate does not filter them, because every why / what-property /
where-from field is *present*; the content is what is wrong. Presence is
what the gate checks. The layers that actually catch a weak scout are
falsification, preflight and the probes, and they are priced in probe
cycles. "Bring your own scout" survives this measurement — with a floor.
