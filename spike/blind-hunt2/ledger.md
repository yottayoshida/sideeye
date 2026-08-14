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
  `/tmp/blind2/...`. khard's refusal is our configuration bug, not the target's
  answer.
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
