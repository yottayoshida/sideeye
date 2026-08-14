# Campaign ledger — every consultation, deviation, and breach, as it happens

Seal A artifact (ADR 0012). Append-only; entries are dated and never rewritten. The
sealed-at-A sections of `candidates.md` record what was consulted *before* the seal;
this file records everything after it.

What belongs here:

- **Source consultations** under issue #83's operational-facts carve-out: the file
  looked at, the single fact taken (state directory location, setup command), and why
  the docs did not answer. Nothing else may be taken from source.
- **Invocation edits**: diffs to `invocations.tsv` after its first commit, with the
  permitted source (`--help`, man page) each change came from.
- **Wrapper edits after Seal B** — these mark the checker *sighted* (ADR 0012 breach
  handling); the entry says so explicitly.
- **Reviewer-covenant breaches**: who named target internals or known issues, in which
  PR, and which target left the blind set because of it.
- **Experimenter deviations**: any forbidden source consulted, even by accident. The
  target leaves the blind set (before Seal B: appended to `burned.txt` and selection
  re-runs over the sealed order; after Seal B: the campaign ends — ADR 0012 breach
  handling).
- **Sweep re-runs**: if an invocation was broken and the sweep ran again, both
  manifests stay committed and the entry says what changed and why — an unrecorded
  tune-and-re-sweep is selection steered by exit codes.

## Entries

(none yet — the campaign has not passed Seal A)
- **2026-08-13 (between the seals) — candidate installation.** All five candidates
  pinned into the container image (`spike/Dockerfile`): apt `abook` 0.6.1-2,
  `hledger` 1.25-2 (bookworm); pip `topydo==0.14`, `khard==0.21.0`, `khal==0.14.0`.
- **2026-08-13 — permitted-source consultations for the invocations** (all
  `--help`/subcommand help inside the container, official docs on the web, and
  normal-run observation; no traces, no source, no bug trackers):
  - topydo: `topydo help` (`-t` todo file, `-d` archive file, `add`/`do`
    subcommands). Normal run observed: `add` then `do 1` completes and archives,
    both files in one directory, exit 0.
  - khard: `khard --help`, `khard new --help` (`-c` config, `-a` addressbook,
    `-i` input file). Minimal `khard.conf` format from khard.readthedocs.io
    (addressbooks section with `path =`). Normal run observed: `new -a main -i`
    creates one `.vcf` with a randomly named file, exit 0. **Config choice**:
    template input via file, not stdin — the exploration engine gives the child
    no stdin.
  - abook: `abook --help`. `--add-email` needs stdin (unusable here);
    `--convert --outformat abook --outfile` is the non-interactive writer.
    Normal run observed: converts a vCard into a native addressbook file, exit 0.
  - khal: `khal --help`, `khal new --help`; minimal config (calendars path +
    required locale block) from khal.readthedocs.io/configure. Normal run
    observed: date arguments must match the configured `longdateformat`
    (`%d.%m.%Y`); `new` creates a randomly named `.ics`, exit 0. **Config
    choice**: khal's own database stays under `$HOME` (ambient, outside the
    watched state); the declared state is the vdir only.
  - hledger: `hledger import <file.journal>` appends to the `-f` journal,
    exit 0, observed. Setup seeds the journal via `/bin/cp` (setup runs before
    recording; any tool is allowed there).
- **2026-08-13 — sweep environment (ambient, applies to all candidates):**
  `HOME=/tmp/blind/home` exported in the container shell that runs the sweep, so
  no candidate writes into the image's real home. Recorded here because the
  invocations file cannot carry environment.

- **2026-08-14 — declaration-phase consultations (all permitted sources; no traces,
  no crash experiments, no source, no bug trackers):**
  - topydo 0.14 README (`raw.githubusercontent.com/topydo/topydo/0.14/README.md`):
    the "fully todo.txt compliant" claim; the pointer to the TiddlyWiki docs.
  - topydo 0.14 documentation (`.../0.14/docs/index.html`, TiddlyWiki): tiddlers
    extracted into `declaration/topydo/transcripts/docs-tiddlers.txt` — Backups
    (`.todo.bak` beside todo.txt, holds both files, written after each modification),
    ConfigBackupCount (default 5, "Set to 0 to disable backups"), Archiving
    ("the completed item is *moved* to done.txt"), revert (backup-matching refusal
    rule), Configuration (config search order incl. cwd files), per-subcommand
    pages. **Changelog tiddlers deliberately not extracted** — fixed-bug listings
    are known-issue reports.
  - todo.txt format specification (`todotxt/todo.txt` README, followed from the
    docs' Format tiddler): Complete Tasks rules 1–2. Saved as
    `transcripts/todotxt-spec.md` (the ADR 0012 todo.txt carve-out's cited spec).
  - `topydo help`, `topydo -v`, and all fifteen per-subcommand helps, inside the
    pinned container: `transcripts/help.txt`, `transcripts/help-subcommands.txt`.
  - One normal (non-crash) run of each of the eleven declared write subcommands:
    `transcripts/normal-runs.txt`. Facts taken: every declared shape exits 0
    without interaction; numbering is insertion order; `do` writes
    `x <date> <date> <text>` into done.txt; `revert ls` prints times at second
    precision; `ls -x` does not list a task that acquired a dependency (so the
    declared checkers grep the files, not the listing); a post-subcommand `-C`
    is not recognized (not used anywhere declared).
- **2026-08-14 — config choice (declared, one deviation from defaults):**
  `backup_count = 0` for the ten non-revert operations (`ops/nobackup.conf`).
  Reason: the backup store's second-precision times would make sideeye's
  un-killed baseline world irreproducible byte-for-byte, refusing every run as
  `baseline_violates_invariant` for the timestamp alone (the watson precedent).
  revert keeps backups — they are its input. Cost stated in `declaration.md`:
  the backup subsystem's crash surface is probed only through revert.
- **2026-08-14 — green-side validation (normal state only, wrapper never saw a
  failure):** for each declared operation — `setup.sh`, the toml's operation
  string verbatim, then `check.sh` — all eleven exit 0, `.todo.bak` absent for
  the ten configured ops and present for revert: `transcripts/config-verification.txt`.
  Toml parse validation ran on the host sideeye binary with a nonexistent shim:
  all eleven parse and stop at state resolution (exit 3) — **no topydo execution**.
  The sweep remains the only sideeye↔topydo contact before Seal B; `sideeye
  preflight` was not run on any declared define.
- **2026-08-14 — deviation, caught and repaired: the ledger briefly broke its own
  append-only rule.** The between-the-seals commit (`6a28ae0`) *replaced* the sealed
  placeholder line "(none yet — the campaign has not passed Seal A)" instead of
  appending below it, which verify-seals A3 (byte-prefix) correctly failed in this
  session's pre-PR check — the verifier's first real catch. The placeholder is
  restored above so Seal A's ledger is again a byte prefix of this file; the bytes,
  not the prose order, carry the append-only property, so the stale "none yet" line
  now sits above real entries and that is the honest shape of the repair. Nothing
  else was altered.
- **2026-08-14 — checker red-side sanity, blind-preserving:** `check.sh` was shown
  to fail (exit 1, correct message) on three hand-fabricated *well-formed* states —
  declared task in neither file, in both files, a non-`x` line in done.txt — plus a
  green control. The states were written by the test script, not produced by topydo;
  topydo itself only ran `ls` over well-formed files (normal behavior). No topydo
  failure mode was observed; the checker's red side against real crash states
  belongs to sideeye's falsification gate after Seal B.
  `declaration/topydo/transcripts/checker-red.txt`.
- **2026-08-14 — R1 review of the declaration (external, covenant-instructed), and
  what it changed.** The reviewer was bound by the ADR 0012 covenant (told not to
  name target internals or known issues; it complied — no burn). Recorded here
  because several findings correct entries above:
  - **Correction to the parse-validation claim above**: "all eleven parse" was
    measured with the *host* binary (v0.7.0), which is not the revision this
    branch seals — the branch bases on the Seal A merge, which predates the
    `expected_status` key the tomls use. The claim holds for the v0.7.0 schema
    only; how the campaign base resolves this is recorded in the BUILDLOG and the
    PR discussion, not silently.
  - **Correction to the config-choice entry above**: "would be refused for the
    timestamp alone" overstated the permitted evidence. What normal runs showed is
    only that `revert ls` *prints* second-precision times; whether the watched
    backup bytes actually vary between baseline runs is deliberately unmeasured
    (measuring it would be engine-over-target observation). The choice stands, now
    stated as a pre-registered refusal risk — wording fixed in `declaration.md`
    and `ops/nobackup.conf`.
  - **Inventory made complete and form-honest**: `ls` and `dep rm` are now
    *declared* (thirteen operation forms across twelve subcommands) instead of
    half-classified; every unexercised documented form is listed per subcommand
    with no vocabulary claim attached. New permitted-source observations for this:
    one normal run each of `dep rm 1 to 2` and `ls` (regenerated
    `transcripts/normal-runs.txt`), and the lscon/lsprj doc tiddlers appended to
    `transcripts/docs-tiddlers.txt` ("Prints a sorted list ..." — the
    not-stateful verdicts are now doc-backed).
  - **Checker hardened, still blind**: I-Q accepts the documentation's padded
    numbers; I-C requires the task as a whitespace-delimited token (an embedded
    substring is not survival); I-F enforces the completion date after the `x`
    (spec rule 2). Green side re-proven for all thirteen ops
    (`transcripts/config-verification.txt`); red side re-proven with the
    fixtures and commands committed (`checker-red-test.sh`,
    `transcripts/checker-red.txt` — five red cases + green control). The
    fabricated states remain user-authored text files; the only topydo
    invocation over them is `ls`, a query over externally-edited files, which
    the target's own docs treat as a normal scenario.
  - The topydo 0.14 README consulted at declaration time is now committed as
    `transcripts/topydo-readme.md` (it was cited but not reproduced).
- **2026-08-14 — base resolution and the recorded re-sweep (the R1 base finding
  above, resolved).** The campaign branch was rebased from the Seal A merge
  (`217ec4f`, 16:51) onto the v0.7.0 merge (`a21b093`, 20:39 the same day), so the
  sealed revision carries the engine the exploration must run — contract v8, whose
  changes over v7 are PASS-side soundness fixes — and the `expected_status` schema
  the declaration uses. Verifiable basis: every Seal A artifact is byte-identical
  between the two anchors (`git diff 217ec4f a21b093 -- spike/blind-hunt/` is
  empty), PRD.md is untouched, and DESIGN.md differs by two lines in the §12
  define-key note — the §17/§18 criterion wording the campaign is scored against
  did not move. verify-seals is run with A=`a21b093`; the true chronology stays
  this ledger's: procedure sealed and pushed at `217ec4f`, first sweep 17:05–17:06
  on the v7-era engine, rebase and everything after on 2026-08-14.
  **Because the engine moved, the sweep was re-run once, recorded**: same
  committed `invocations.tsv` (the manifest's hash is unchanged —
  `89f8f325…`), fresh container, engine `sideeye 0.7.0 (trace contract v8)`.
  Verdicts were identical to the first sweep: topydo/khard/abook/khal exit 0,
  hledger exit 2 (reason still sealed, still unread). `select.sh` recomputed:
  **topydo**. The first sweep's manifest stays committed beside the new one
  (`sweep-manifest.2026-08-13.v7-engine.json`); both sets of sealed reports are
  retained under `artifacts/` (`sealed-reports/` and `resweep-v8/sealed-reports/`),
  none read. This is the ADR 0012 recorded re-run shape: nothing tuned, nothing
  selected by exit codes — the same spelling, a newer engine, the same answer.
- **2026-08-14 — parse validation redone on the right binary.** All thirteen tomls
  re-validated against the binary built from the rebased branch itself, inside the
  pinned container (`sideeye 0.7.0 (trace contract v8)`, nonexistent shim): every
  one parses and stops at state resolution (exit 3). No topydo execution. This
  replaces the host-binary measurement the R1 entry above corrected.
- **2026-08-14 — the exploration ran; the campaign's blind phase is over.** Seal B is
  the merge commit `5a034aff`; `run.sh` explored all thirteen declared operation
  forms from it, in a clean tree, in the pinned container. `verify-seals a21b0933
  5a034aff <run-manifest> <sealed-reports>` returns ALL SEAL CHECKS PASSED (R1
  audited). Results: 12 FAIL, 1 PASS (`ls`, the declared read-only form, recorded
  zero state-changing operations as expected). Raw reports, saved cases and the
  post-seal analysis live in `spike/blind-hunt/analysis/`.
  **From this entry on, the blind restrictions no longer bind** — the declaration is
  frozen and the measurement it was written for has happened, so reading traces or
  behavior of topydo is now ordinary analysis. **Two things stay restricted by
  choice**: the target's bug tracker is still unread (novelty is unclaimed until a
  deliberate check), and `spike/blind-hunt/declaration/` is not edited (an edit
  would retroactively mark the checkers sighted, ADR 0012).
- **2026-08-14 — correction recorded before it could become a claim.** The first
  reading of the recovery measurements was "the data is unrecoverable": plain
  `revert` both refused and, in other worlds, undid an older command. Measuring the
  documented forced form (`revert <NUMBER>`, one sentence further down in the same
  help text) showed full recovery in every case tried. Nothing wrong was published;
  the entry exists because the near-miss is the reportable part.
