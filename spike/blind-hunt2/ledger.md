# Campaign 2 ledger — every consultation, deviation, and breach, as it happens

Seal A artifact (ADR 0012 via ADR 0015). Append-only; entries are dated and never
rewritten. The sealed-at-A sections of `candidates.md` record what was known before
this campaign's seal — including, per ADR 0015, everything inherited from campaign 1's
ledger; this file records everything after it.

What belongs here is what campaign 1's ledger held: source consultations under the
operational-facts carve-out, invocation edits with their permitted source, wrapper
edits after Seal B (they mark the checker sighted), reviewer-covenant breaches,
experimenter deviations (burned targets), and sweep re-runs with both manifests kept.

Two campaign-2 additions. First (ADR 0015 §2): the declaration phase must also
record the documentation consulted for the **recovery-path rule** — the full
enumeration of recovery/undo/repair command forms the docs name (with citations),
or the explicit finding that they name none. Second (ADR 0015 §3): the sweep
entry must record the **image identity** (`docker image inspect` ID of
`sideeye-blindhunt`) alongside the ambient environment — self-reported, said so.

## Entries

(none yet — the campaign has not passed Seal A)
- **2026-08-14 — the first Seal A (merge `459615a8`) is VOID; this branch re-seals.**
  The between-seals sweep ran once against the sealed rows (fresh container, engine
  `sideeye 0.7.0 (trace contract v8)` built from the seal merge, image
  `sideeye-blindhunt:latest` ID `sha256:d3d28e791276…`, SWEEP_IMAGE mis-captured as
  empty in the manifest — the inspect call needed the `:latest` tag) and displayed,
  per the harness contract, exit codes only: **khard 2 / abook 0 / khal 0 /
  hledger 2**. khard's flip against campaign 1's public verdict (0 → 2) prompted a
  look at our own committed artifacts — not at any sealed report, which remain
  unread — and the cause is a **contradiction inside the seal itself**:
  `configs/khard.conf` and `configs/khal.conf` still hardcode campaign 1's state
  roots (`/tmp/blind/...`) while the sealed `invocations.tsv` watches
  `/tmp/blind2/...`. With the sealed reports unread and no controlled re-run, this
  does not prove the mismatch *caused* the refusal — what it establishes is that the
  apparatus contradicted itself, so **that verdict is uninterpretable**, whatever
  produced it.
  **Why void instead of proceeding with the machine-selected abook**: the
  pre-registered khard refusal risk (candidates.md) makes an apparatus bug that
  knocks khard out of selection indistinguishable, to a skeptical reader, from
  steering — the exact optics the seals exist to kill. And an in-place fix is
  impossible by design: configs and rows ride the A2 no-touch set. The only honest
  exit is to void before any declaration exists (blindness cost: four exit codes,
  displayable by contract) and re-seal with consistent paths, giving khard its
  fair shot.
  **The falsified claim is recorded as falsified**: the first seal's ADR text said
  the pre-seal resolution check meant freezing "does not risk a spelling-error
  dead end". It checked command resolution and file existence, not the paths
  *inside* config files; both the author and the R2 reviewer certified the configs
  as dependency-free while `/tmp/blind` sat in two of them. The re-seal adds a
  mechanical consistency check (every `/tmp/...` path in every config must sit
  under an invocation state root) — run green on the fixed tree before this seal.
  The superseded manifest is committed beside this entry
  (`sweep-manifest.2026-08-14.superseded-voided-seal.json`); its sealed reports
  are retained unread under `artifacts/sweep/`.
- **2026-08-14 — what the re-seal adds beyond the two fixed paths.**
  `check-config-paths.sh` (new Seal A artifact): every absolute `/tmp` path in every
  sealed config must lie under a state root named in `invocations.tsv`. Falsified
  before being trusted — red on the exact defect that voided the first seal (a
  config naming campaign 1's root), red on a sibling-but-wrong root, and **exit 2
  rather than success when it cannot look** (no state roots / no config files),
  plus a green control on the fixed tree. Also: `.gitignore` made
  campaign-agnostic (`spike/blind-hunt*/artifacts/`,
  `spike/blind-hunt*/configs/.latest.*`) — the campaign-1-specific patterns did not
  cover campaign 2, so the sweep's sealed reports and hledger's import sidecar were
  both staged for commit and had to be un-staged by hand. Verified with
  `git check-ignore` that the new globs cover campaigns 1, 2 and a hypothetical 3
  while leaving sealed configs and manifests tracked.
- **2026-08-14 — the void is machine-readable, and the verifier says so itself.**
  Measured first: passing the voided anchor `459615a8` to `verify-seals.sh` already
  failed (A2 walks the whole A..B range, and the re-seal necessarily edits sealed
  paths). That refusal was a consequence, not a statement, so the re-seal adds
  `voided-seals.txt` (one SHA per line, sealed in the inventory) and a verifier
  preamble that refuses a listed anchor with exit 2 and names the reason. Falsified
  both ways: the voided anchor now exits 2 with the explanation, and a non-voided
  anchor still runs the full battery unchanged (checked that the new guard does not
  swallow the existing checks — the ADR 0012 lesson that a new guard can blind older
  ones). The list is the label; A2 remains the lock.
- **2026-08-14 — R1 on the re-seal (external, covenant-instructed; no breach): eight
  findings, all applied.** The guard added at the re-seal was itself the main target,
  which is the right outcome for a guard written in a hurry:
  - **It compared each config path against *any* invocation root** — a config
    belonging to one row could agree with a different row's state and pass. Now the
    check is per row: config files are discovered from the row's own setup/operation
    arguments, and compared only against that row's state root.
  - **Containment was lexically unsound**: the reverse branch accepted any *ancestor*
    of a state root (a parent directory watching unobserved state passed), and `..`
    was never considered. Now strictly under-or-equal, on normalized paths, with `..`
    rejected outright rather than resolved.
  - **"Exit 2 when it cannot look" was incomplete**: extra arguments were ignored,
    unreadable files and malformed rows exited 1 through Python, and the bare path
    `/tmp` never matched the regex. All four closed.
  - Re-falsified after the rewrite: **12 cases**, including one red per hole above
    (cross-row root, parent root, `..` escape, bare `/tmp`), a green for a deeper path
    inside the row's own root, and four cannot-look refusals.
  - **The sweep harness would have destroyed the voided evidence**: `mkdir -p`
    accepted an existing output directory and truncated the manifest and reports in
    place — and the retained voided run sits in exactly such a directory. The harness
    now refuses an existing output dir, as it already refused existing state roots.
    The voided run was moved to `artifacts/sweep-voided-459615a8/` first, and its
    reports were re-verified against the superseded manifest (all four hashes match)
    **without reading them**.
  - **The account overclaimed causation**: with the reports unread and no controlled
    re-run, the path mismatch does not prove it produced khard's refusal. Reworded in
    the ledger, the ADR and the BUILDLOG to what is established — the apparatus
    contradicted itself, so that verdict is uninterpretable, which is all the void
    decision needed.
  - `.gitignore` narrowed from `blind-hunt*` to `blind-hunt[0-9]*` (plus the campaign-1
    literal): the wildcard also swallowed unrelated siblings. Verified both directions.
  - The stale "none yet" placeholder is kept but annotated — the ledger's bytes are an
    append-only prefix the verifier checks, so it cannot be deleted, only explained.
- **2026-08-14 — a note about the line above the entries.** The placeholder "none yet
  — the campaign has not passed Seal A" is false from the first entry onward and is
  kept verbatim anyway: the ledger's bytes are an append-only prefix the verifier
  checks (A3), so a stale line can be explained but not edited. **Measured, not
  assumed** — rewriting it as an annotation broke the prefix, and the self-check run
  before committing caught it; the sealed bytes were restored and the explanation
  moved here, where appending is the sanctioned move.
- **2026-08-14 — correction to the void entry above (R2).** That entry says "the cause
  is a contradiction inside the seal itself" and then, two sentences later, that the
  evidence does not establish causation. The first clause is the overclaim this
  campaign keeps having to unlearn, and it cannot be edited out — the ledger is
  append-only — so it is corrected here: **what is established is the contradiction
  and therefore the uninterpretability of that verdict**, not that the contradiction
  produced it. Nothing in the void decision rests on the stronger reading.
- **2026-08-14 — R2 (external, confirm-only): 6 of 8 resolved, 2 sent back, both fixed.**
  (a) The guard's cannot-look contract still leaked one way: `UnicodeDecodeError` is a
  `ValueError`, not an `OSError`, so an undecodable invocations file exited 1 through
  the traceback instead of exiting 2 as "could not look". Caught both files' decode
  errors; the red suite now runs **14 cases**, adding an undecodable invocations file
  and an undecodable config. (b) The causal overclaim was only half-corrected — the
  void entry still opens with "the cause is", contradicting its own caveat two
  sentences later. Corrected in an appended entry above rather than edited, since the
  ledger is append-only.
- **2026-08-14 — the apparatus, made rehearsable before this seal merges.** Four
  additions, all outside the sealed set except one:
  - **verify-seals gains R3** (sealed tooling, amended on the open re-seal branch):
    when a run manifest is supplied, its `engine_sha256`/`shim_sha256` must equal the
    committed sweep manifest's — the exploration provably ran the binaries the sweep
    ran. The declaration phase's `run.sh` must therefore record both fields.
  - `spike/rehearse-campaign.sh`: the full pipeline against synthetic targets in a
    scratch repository — real tooling byte-for-byte, defects planted one at a time
    (A2/A3/B3/B4/R1/R3/void-anchor/config-guard/walker/ledger-tool/driver refusals),
    then a real container sweep through the driver ending ALL SEAL CHECKS PASSED
    (R1 audited). 26 drills, all green after two real catches on the first run:
    this host's docker resolves image names flakily (both resolvers now accepted),
    and /bin/cp is refused by preflight (copy_file_range, outside the trace
    contract) — the toy now writes through dd. Rule: rehearse green before any
    Seal A PR and after any tooling change.
  - `spike/campaign-driver.sh` (unsealed by design — it carries no verdict logic):
    phases refuse out-of-order execution; merges and commits stay human.
  - `spike/ledger-append.sh`: the only sanctioned ledger writer — appends, then
    proves the result still extends HEAD, restoring on failure. This entry is its
    first production use.
- **2026-08-14 — delta review on the apparatus (external, fixed axes applied to their
  own delta): seven findings, all applied.** The two fixed review axes did exactly
  what they were installed to do — they caught the apparatus entry's own claims:
  the rehearsal's "entire pipeline" had a fabricated exploration (now real: the
  Seal B carries a runner, the driver runs it, R1/R3 audit the manifest it wrote),
  and two driver drills passed on the wrong guard (every red now asserts the
  firing guard's message). Also fixed: driver `select` now requires a clean tree
  (it read worktree files while B3 checked HEAD); outdir arguments are
  canonicalized, confined to the repository, and charset-guarded before container
  interpolation; `ledger-append.sh` canonicalizes its directory argument (a
  relative path used to bypass the HEAD baseline — red-tested now in both
  directions); verify-seals R3 requires both identity fields to be real SHA-256
  digests on both sides and handles unparseable manifests as failures (shim
  mismatch, missing field, and matching non-digests each have a red drill); the
  campaign walker's remaining predicates (non-executable checker, exemption
  non-inheritance, pre-sweep skip, empty-tree refusal) moved from a scratchpad
  suite into the committed rehearsal. 41 drills, all green, rerun after the fixes.
- **2026-08-14 — confirm round: 6 of 7 resolved, the seventh fixed.** `canon_out`
  still accepted `..` segments — the charset guard allows `.`, so `/repo/a/../../x`
  slips the textual under-repo test while escaping the repository. Refused now
  (never resolved), matching the sealed config check's treatment of `..`; a red
  drill covers the escape shape. Rehearsal: 42 drills, all green.
- **2026-08-14 — the campaign-2 sweep, run once against the re-sealed apparatus.**
  Seal A is the PR #107 merge `8878df82`. The sweep ran through the phase driver
  (which found one more apparatus bug on the way and refused to proceed until it
  was fixed: `image_id` failures were swallowed by the command substitution, so a
  stopped docker daemon produced an EMPTY image name that reached `docker run` —
  the fix stops the driver, red-measured against an unreachable DOCKER_HOST).
  Environment: image `sideeye-blindhunt:latest` ID `sha256:d3d28e791276…`
  (recorded in the manifest via SWEEP_IMAGE), engine and shim SHA-256 in the
  manifest, engine built from the Seal A merge. **Verdicts, exit codes only:
  khard 0 / abook 0 / khal 0 / hledger 2** (reason sealed, unread, as ever).
  With the config/invocation contradiction fixed, khard's verdict returned to
  campaign 1's public value — consistent with the voided sweep's refusal having
  been our apparatus, though nothing stronger than consistency is claimed. The
  sealed reports stay local under `artifacts/sweep-8878df82/`; only hashes travel.
- **2026-08-14 — declaration-phase consultations for khard (all permitted sources;
  no traces, no crash experiments, no source, no bug trackers):**
  - `khard --version`/`--help` and all sixteen per-subcommand helps, inside the
    pinned container (`transcripts/help.txt`, `help-subcommands.txt`; the
    subcommand help machinery requires a config — the sealed sweep config was
    passed, read-only).
  - The v0.21.0 documentation: man pages khard(1), khard-subcommands(1),
    khard.conf(5), plus the command-line and scripting pages
    (`transcripts/man-*.txt`, `docs-*.txt`). Facts taken: config syntax and the
    four config sections (no filename/UID setting exists); "vCard files hold one
    VCARD record each, .vcf extension" (the carve-out sentence); merge_editor is
    documented as interactive; no recovery/undo/repair command anywhere.
  - RFC 6350 as the vCard normative spec (BEGIN/END delimiters, FN required),
    via ADR 0012's carve-out — cited in the checker, not transcribed.
  - One normal (non-crash) run per declared form plus determinism and
    interactivity probes (`transcripts/normal-runs.sh` → `normal-runs.txt`):
    new mints a random UID as filename and content plus second-precision REV;
    copy re-mints both; remove --force is non-interactive and byte-deterministic
    across identical stores; move preserves filename and bytes; edit waits for
    confirmation even with -i (10s timeout); add-email's Select? prompt repeats
    unbounded on EOF (~200MB in 5s, capped); merge errors without a merge
    editor; `list` on an empty addressbook exits 1 — the observation that put a
    conserved bystander in every declared state.
- **2026-08-14 — the khard declaration, written blind.** Four operations declared
  (new / remove --force / move / copy — move is the cross-file window), three
  subcommands excluded as interactive with evidence, nine as not-stateful.
  **Recovery-path rule: vacuous discharge** — the enumeration over all sealed
  doc transcripts finds no recovery/undo/repair command form; stated in the
  declaration with its consequence (a damaged store has no documented in-tool
  recovery). **Two pre-registered refusal expectations** (new, copy: random
  UID/REV vs the byte-reproducible baseline — the watson shape); remove and move
  are the live searches. Verification, blind-preserving: checker red-suite 12
  cases committed with fixtures (`checker-red-test.sh` → `transcripts/
  checker-red.txt`), green side 4/4 (setup → verbatim toml operation → checker;
  `transcripts/green-run.txt`), all four tomls parse on the binary built from
  this tree inside the pinned container (stop at state resolution; khard not
  executed). `sideeye preflight` was deliberately NOT run on any declared
  define; the sweep remains the only sideeye↔khard contact.
- **2026-08-14 — khard is burned (breach before Seal B; ADR 0012).** The
  declaration's red suite (`checker-red-test.sh`, committed at a459995)
  fabricated stores holding deliberately mis-shaped vCards and ran `check.sh`
  over them; the checker's first step is the `khard -c ... list` liveness
  query, so khard ran over a malformed store and its failure response was
  recorded in the committed transcript (`checker-red.txt` line 13 ends with
  khard's own message on an unparsable .vcf: "Use --debug for more information
  or --skip-unparsable to proceed"). That is pre-Seal-B observation of target
  failure behavior. The red suite's header argued it was safe ("khard itself
  only ever runs `list` over these stores") — the claim did not cover what the
  measurement actually touched. The declaration and its transcripts were
  committed as one batch, so "the observation did not shape the declaration"
  is not provable from history; there is no cure (blind is once per target).
  Ruled a burn 2026-08-14. Handling per ADR 0012, before Seal B: khard is
  appended to `burned.txt`, the declaration leaves the tree in this commit
  (history keeps it at a459995), and selection re-runs over the sealed order
  with the burned name skipped. Structural change carried to the next
  declaration: the checker inspects files first and queries the target last,
  and red fixtures are well-formed only (an empty store — documented-normal —
  is the one permitted refusal shape).
- **2026-08-14 — declaration-phase consultations for abook (all permitted
  sources; no traces, no crash experiments, no source, no bug trackers):**
  - `abook --help` and `abook --formats` inside the pinned container
    (`declaration/abook/transcripts/help.txt`, `formats.txt`).
  - abook(1) and abookrc(5) man pages, taken from the pinned package itself:
    the slim image strips /usr/share/man, so `sources.sh` apt-downloads the
    EXACT installed version (0.6.1-2+b1, asserted equal before unpacking) and
    unpacks it with dpkg-deb into scratch — nothing is installed, the sealed
    image is unaltered, and the deb's sha256 is printed by the sources run.
  - One normal (non-crash) run per candidate form plus determinism and
    interactivity probes (`transcripts/normal-runs.sh` → `normal-runs.txt`):
    convert vcard→abook is byte-deterministic across two runs, as is
    abook→vcard export; convert onto an EXISTING outfile refuses ("cannot
    write file", exit 1) and leaves the store byte-identical; --mutt-query
    exits 0 on a match, 1 "Not found" on no match, 1 "Cannot open database"
    on an empty or absent datafile; bare `abook` needs a terminal (exit 1
    without one); --add-email and --add-email-quiet on stdin EOF print "Valid
    sender address not found", exit 0, and write no datafile. The native
    store shape was observed once (leading `# abook addressbook file`
    comment, a `[format]` block, numbered `[N]` sections with `name=` /
    `email=` lines). Every probe store was written by abook itself in the
    same script, empty, or absent — no mis-shaped store was ever given to the
    target (the khard burn's structural rule, applied at observation time).
  - Facts taken: the CLI surface is --convert / --mutt-query /
    --add-email(-quiet) / --formats plus the interactive TUI; abookrc is
    optional with documented defaults (abookrc(5)); no recovery, undo, or
    repair command appears anywhere in these pages.
- **2026-08-14 — abook apparatus-phase target contacts (all documented-normal;
  no crash experiments, no traces, no mis-shaped store ever offered):**
  - `make-goldens.sh` ran three vcard→abook converts to mint the committed
    golden stores (grace / pair / impostor) — abook's own bytes as fixtures,
    resting on the observed byte-determinism (normal-runs §2).
  - The checker red suite (`checker-red-test.sh` → `transcripts/
    checker-red.txt`, 14 cases green) runs REAL abook only as `--mutt-query`
    over abook-written golden stores (the impostor anchoring probe and its
    golden positive control); every ill-behaved-binary branch (exit codes,
    match-line counts, byte-writing queries, hangs, outfile creation) is
    exercised through the checker's CHECK_ABOOK stub seam — the target does
    not run in those cases at all.
  - The green run (`transcripts/green-run.sh` → `green-run.txt`, fails=0)
    executed each declared operation once, verbatim from its sealed toml,
    over setup states cp'd from the goldens: import rc 0, export rc 0,
    refused rc 1 — each equal to its toml's expected_status — followed by a
    green checker. The three tomls were each also fed to this tree's engine
    with no state root: all stop at state resolution (rc 3) with zero side
    effects, abook not executed.
  - Engine identity on the transcript: `sideeye 0.7.0 (trace contract v8)`,
    engine and shim SHA-256 equal to the committed sweep manifest's values
    (the R3 leg's comparison, pre-verified at declaration time).
- **2026-08-14 — R1 of the abook declaration: corrections to earlier entries
  of this ledger (append-only, so corrected here rather than edited):**
  - The consultation entry's "convert onto an EXISTING outfile … leaves the
    store byte-identical" was, at the time it was written, backed by a
    printed before/after and no `cmp` — the claim exceeded its measurement.
    normal-runs §4 now runs `cmp` and the re-run measured: byte-identical
    (the probe re-run is a normal-run contact of the same class).
  - The apparatus entry's "zero side effects" for the toml parse probes
    claimed more than the probe inspected. The probed paths are the state
    root, the work path, and $HOME/.abook; the claim is now stated at that
    width in green-run.sh and here.
  - The apparatus entry implied the sources provenance (deb version assert,
    sha256) was on the record; it was only ever on a terminal. It now lands
    in the committed `transcripts/sources-provenance.txt`, which also ties
    bare `abook` to /usr/bin/abook in the pinned image.
  - The goldens' "written by abook itself" now has a standing gate: the red
    suite regenerates all three from the committed inputs into scratch and
    byte-compares against the committed goldens on every run (17 cases
    total, transcript committed). Green additionally asserts each
    operation's documented effect, and run.sh fails closed on a missing or
    unparsable report.
  - Real-abook contact during the red suite, restated precisely: queries
    over abook-written goldens, plus the provenance case's converts whose
    vCard inputs are the committed hand-authored well-formed files — the
    documented-normal input class. No mis-shaped native store reaches the
    target anywhere in the apparatus.
