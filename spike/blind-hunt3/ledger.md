# Campaign 3 ledger — every consultation, deviation, and breach, as it happens

Seal A artifact (ADR 0012 via ADR 0015 and ADR 0016). Append-only; entries are
dated and never rewritten — written only through `spike/ledger-append.sh`. The
sealed-at-A sections of `candidates.md` record what was known before this
campaign's seal, including everything inherited from the prior campaigns'
ledgers; this file records everything after it.

What belongs here is what the prior ledgers held: source consultations under
the operational-facts carve-out, invocation edits with their permitted source,
wrapper edits after Seal B (they mark the checker sighted), reviewer-covenant
breaches, experimenter deviations (burned targets), and sweep re-runs with
both manifests kept. The campaign-2 additions carry: the declaration phase
records the documentation consulted for the recovery-path rule (ADR 0015 §2),
and voids land in `voided-seals.txt` with their narrative here.

## Entries

- **2026-08-14 — campaign 3 apparatus created (pre-seal).** Tooling copied
  from campaign 2's sealed copies with paths adapted (`blind-hunt2`→
  `blind-hunt3`, `/tmp/blind2`→`/tmp/blind3`), then swept for leftovers by
  grep (zero hits) — the campaign-2 void class (a config naming another
  campaign's state root) is what that scan exists to keep out, and
  `check-config-paths.sh` remains the mechanical gate. Candidates inherited
  per ADR 0016: khal then hledger (khard burned, abook consumed). The khal
  random-`.ics` refusal risk and the todoman storage-class disclosure duty
  carry from the prior seals, restated in `candidates.md`. No target was
  executed during this construction.
- **2026-08-14 — Seal A R1: five findings, all adopted before the seal.**
  The P1 sat in the void-class gate itself: `check-config-paths.sh` resolved
  config references by basename, so a stale reference to another campaign's
  configs would have been checked against THIS campaign's file and passed —
  the contradiction the gate exists to refuse, reachable through the gate.
  Discovery now requires the reference to name this campaign's mounted
  configs dir (`/work/spike/blind-hunt3/configs/`) and the file to exist;
  falsified both ways in scratch before this entry (foreign reference →
  refused, pinned message; missing config → refused; real rows → green).
  Also adopted: eleven tool-comment sites had rewritten campaign-2 history
  as campaign-3 findings during the mechanical adaptation — restored to
  honest attribution ("carried" where inherited); the rehearsal's fabricated
  campaign name is guarded at run time (must not exist in the repo, must not
  equal CAMP) instead of hoped unique; the earlier "zero hits" scan claim in
  this ledger is hereby scoped to the operational apparatus files — the
  ledger narrative itself names campaign 2 legitimately, so a whole-tree
  grep does hit; and the verifier's header summary now states B1 as the code
  checks it (invocations sealed at A; only the manifest first appears at B).
- **2026-08-14 — the campaign-3 sweep ran once, through the driver, from
  Seal A `2239fba`.** Image `sideeye-blindhunt@sha256:d3d28e791276…` (recorded
  in the manifest via SWEEP_IMAGE), engine `sideeye 0.7.0 (trace contract
  v8)`, engine and shim SHA-256 in the manifest, invocations hash matching
  the sealed rows. Verdicts, displayed per the harness contract as exit
  codes only: **khal 0 / hledger 2** — the same public values as both prior
  sweeps; hledger's refusal reason remains sealed and unread. The full
  reports went unread into `artifacts/sweep-2239fba/sealed-reports/` (local;
  only their hashes travel in the manifest). The manifest is committed
  beside the sealed rows in the same commit as this entry.
- **2026-08-14 — declaration-phase consultations for khal (all permitted
  sources; no traces, no crash experiments, no source, no bug trackers):**
  - `khal --help`, all twelve listed commands' `--help`, `--version`, and
    `pip3 show` identity, inside the pinned container
    (`declaration/khal/transcripts/help*.txt`, `sources-provenance.txt`;
    khal 0.14.0, bare `khal` resolves to /usr/local/bin/khal).
  - The version-pinned official usage page,
    khal.readthedocs.io/en/v0.14.0/usage.html, transcribed with tags
    stripped (`transcripts/docs-usage.txt`, 586 lines; fetched via curl —
    khal ships no man pages in the pinned image). Facts taken: import
    syntax and same-UID update semantics ("--batch ... always update");
    `edit` is "an interactive command for editing and deleting events";
    `configure` refuses if a config exists; ikhal deletes marked events
    "when khal exits"; the recovery-vocabulary grep over the whole page
    returns zero hits.
  - One normal (non-crash) run per candidate form plus determinism and
    interactivity probes (`transcripts/normal-runs.sh` → `normal-runs.txt`),
    all in scratch with HOME inside scratch. Measured: import --batch of a
    fixed-UID .ics into a fresh vdir names the file `<UID>.ics` and is
    byte-deterministic across two runs (tree-level diff -r); the same-UID
    --batch update rewrites that file AND leaves extra files with random
    suffixes in the vdir (`.ics2mtnp400`-shaped; names differ across runs —
    a NORMAL-run observation, no crash involved), so import-update is
    baseline-irreproducible and carries a pre-registered refusal
    expectation; `new` mints a random UID-named .ics with DTSTAMP=now
    (two fresh runs differ — the campaign-1 observation, now measured
    precisely); queries (list/search) exit 0 even on no match, change no
    byte of an existing vdir, keep khal's cache under $HOME (outside the
    state root) — and `list` CREATES a missing configured vdir (observed),
    a directory-level write the checker will avoid by querying only
    existing vdirs; interactivity probes: import without --batch prompts
    and aborts on EOF (rc 1), import from stdin errors on EOF (rc 1),
    edit prompts and aborts (rc 1), interactive needs a terminal,
    configure prompts and aborts (rc 1). Every vdir a probe touched was
    khal-written, empty, or absent; the .ics inputs are hand-written
    well-formed iCalendar (the documented input class).
- **2026-08-14 — khal apparatus-phase target contacts (all documented-normal;
  no crash experiments, no traces, no mis-shaped store ever offered):**
  - `make-goldens.sh` ran three fixed-UID imports to mint the committed
    golden EVENT files (grace / ada / impostor) — khal's own serialization
    as fixtures, resting on the observed byte-determinism (normal-runs §1).
  - The checker red suite (`checker-red-test.sh` → `transcripts/
    checker-red.txt`, 15 cases green) runs REAL khal only as `search` over
    khal-written golden stores: the provenance drift-gate (regenerate all
    three goldens into scratch, byte-compare against the committed files)
    and the anchoring probes — which also MEASURED that khal's search is
    substring-matching (the impostor store's `GraceStandupX` line came back
    for the query `GraceStandup`) and that the checker's exact-line
    `grep -Fx` anchor rejects it while accepting the golden's line. Every
    ill-behaved-binary branch (exit codes, unanchored/suffixed/duplicate
    lines, vdir-writing queries, hangs) runs through the CHECK_KHAL stub
    seam — the target does not run in those cases.
  - The green run (`transcripts/green-run.sh` → `green-run.txt`, fails=0)
    spawned setup and check THROUGH THEIR EXEC BITS (ADR 0016 requirement
    3), executed each declared operation verbatim from its sealed toml
    (all rc 0 == expected_status), ran the checker green, and asserted each
    documented effect (import: `<UID>.ics` exists and answers its anchored
    query; update: the subject carries the new SUMMARY — with 2 non-.ics
    leftover files observed, not asserted; new: exactly one new event file
    beside the bystander). The three tomls each stop at state resolution
    (rc 3) with the probed paths untouched; khal not executed there.
  - Engine identity on the transcript: `sideeye 0.7.0 (trace contract
    v8)`, engine and shim SHA-256 equal to the committed sweep manifest's
    values — the R3 comparison pre-verified at declaration time.
