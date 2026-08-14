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
