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
