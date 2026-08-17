# The contract-freeze audit — v1.0 criterion 5

PRD criterion 5 freezes four surfaces at v1.0 — config format, report schema,
exit codes, replay compatibility — and issue #86 added a fifth by decision
(the MCP surface) and defined this audit: every open issue that touches a
frozen surface gets resolved *before* the freeze, because after it, a fix as
filed is a broken promise. "Defer and freeze anyway" is the one outcome this
page exists to prevent.

**Snapshot.** The classification below covers the open-issue set captured by
`gh issue list --state open` at 2026-08-17T00:33:15Z — twenty-six issues,
committed verbatim as `spike/freeze-audit/snapshot-2026-08-17.tsv`. The
table's completeness is checked against that snapshot by
`spike/freeze-audit/check-freeze-audit.sh`, **run at each sweep, not wired
into CI** — this page retires at the v1.0 tag, and a permanent gate for a
retiring page is a layer this repo declines; the run's output is quoted
below. The gate proves on every run that it can go red: it deletes one
classification row from a run-time copy of this page and requires that copy
to fail (the copy is generated, never committed — a committed fixture rots
silently after a re-sweep, and an absent one must not read as a passed
falsification; both failure shapes were measured in review). The snapshot
itself is the gate's trust root and nothing machine-checks it — commit
review does. The sweep was run, not recalled: the set includes issues filed
the same day, some only minutes before the capture, and excludes #87, closed
seventeen seconds before it.

Gate output, 2026-08-17: `ok: the table covers all 26 snapshot issues, and
the gate goes red on a one-row-deleted copy` — with the reverse also
measured once (a forged snapshot row makes it fail, naming the row).

**The rule this declaration carries.** It takes effect at the v1.0 tag, not
today. Before tagging, the sweep is re-run and this page updated for any
issue opened or closed since the snapshot — the audit is a gate, not a
ceremony performed once and aged.

## The declaration: what freezes at v1.0

1. **Config format.** `[world] state`; `[define] setup`, `operation`,
   `check`, `marker`, `expected_status`. Both command spellings: the string
   form with its split-on-spaces, no-quoting rule, and the argv form — one
   line, double-quoted elements, passed verbatim (ADR 0019). Unknown keys,
   malformed values and the array form on non-command keys refuse with named,
   line-numbered errors; relative paths resolve against the toml's directory
   (ADR 0007). Additive keys remain possible; changing the meaning of an
   accepted spelling does not.
2. **Report schema.** The fields, presence rules and `unknown_reason` closed
   set documented in `docs/report-schema.md`, held to the code by acceptance
   check 4 — `oracle_verified` included (#94). The account fields' prose may
   improve between releases; their presence and the machine fields' meaning
   may not (a field would change name, never silently change meaning).
3. **Exit codes.** 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP_ERROR — and UNKNOWN is
   never 0. **No evidence-strength split** (owner decision, 2026-08-17): an
   unverified PASS keeps exit 0, rejected because the flag that produces it
   is the caller's own explicit consent, macOS — where no oracle exists —
   would lose exit-0 passes entirely, and the distinction already lives in
   the designed channel (`oracle_verified`). Declining now means declining
   permanently; that is understood.
4. **Replay compatibility.** A saved case replays across 1.x or refuses
   honestly — `case_no_longer_applies` when the code changed underneath it,
   `contract_version_mismatch` across trace-contract versions — never a
   verdict about a shifted address (ADR 0009, 0014). Version and shape travel
   together (a v1/v2 case cannot carry an argv command). A future trace-
   contract bump is therefore *not* a broken promise: old cases refuse with
   the mismatch named, and that refusal is the promised behavior.
5. **The MCP surface** (decided 2026-08-13, recorded in #86, codified here).
   The two tool names — `sideeye_explore_config`, `sideeye_replay_case` —
   their input schemas, and the isError derivation rule (isError follows the
   verdict structure: real verdicts false, refusals true — ADR 0010).
   Additive extension stays open: new tools, new optional parameters.

## Every open issue, classified

Classes for touchers, per #86's amendment: **A** — the gap can make PASS
overclaim (prose alone cannot retire one; resolution is fix, demote to a
refusal, or narrow the stated promise); **B** — FAIL-side noise or precision
(fix or document); **C** — ergonomics and diagnostics (fix, or defer to 1.x
with a note). Class-A resolutions below are the owner's adjudication
(2026-08-17), taken with the recommendation visible before deciding.

| # | what it is | touches | class | resolution |
|---|---|---|---|---|
| #5 | restore drops FIFOs/sockets/devices; worlds differ from the recorded tree (symlinks fixed in #122) | yes — verdict soundness | A | **demote**: detect a non-regular, non-symlink entry at snapshot time and refuse (UNKNOWN) rather than explore a tree that cannot be reproduced. Fix lands before the tag |
| #6 | the oracle reads any quoted string on a strace line as a path; a target that *prints* a state path draws a false refusal | no — internal parsing precision, fails closed, fix is non-breaking | — | stays open; fixable in any 1.x |
| #10 | macOS Apple platform binaries can never be observed; the docs imply a narrower limit | yes — the stated promise | A-adjacent | **narrow**: `docs/target-classes.md` states plainly that a macOS target must be self-built or self-installed, never an Apple-shipped binary. The README stays under its cut-only order |
| #12 | the omamori dogfood cannot be agent-driven | no — internal tooling | C | defer to 1.x |
| #13 | stdio (fopen/fwrite) invisible to the shim | **stale** — fixed by ADR 0005 (flush-granularity observation), pinned by acceptance check 2u | — | **close as fixed**; the unmeasured reach note (Go, raw syscalls) already lives on the target-classes page |
| #26 | target-chosen paths reach the text report unescaped | yes — report surface (text) | B | document: text-report prose is not frozen and the escaping fix is non-breaking in any 1.x |
| #27 | standard-form L0 misses a file replaced by a directory when pre or post content is empty — a real false-PASS window | yes — the meaning of PASS | A | **fix** before the tag: the standard arm rejects a changed entry kind, with the unit test and control the issue already specifies |
| #35 | L0 flags git's COMMIT_EDITMSG scratch file | yes — FAIL-side precision | B | document as a named precision limit on non-durable files |
| #39 | libc conveniences that mutate state behind the PLT (mkstemp family) | yes — observation reach = PASS meaning | A | **narrow**: on Linux the class fails closed through the oracle (sound today). The macOS narrowing must say *this class*, not only #10's platform-binary limit: target-classes will state that on macOS libc-internal mutations are invisible with no oracle to catch them, so a macOS PASS carries only the `--allow-unverified` weaker claim the README already spells. The interpose-on-first-contact policy (PR #38) stands |
| #46 | no quiescence observation on the stdout capture under a tolerated boundary — a marker could silently vanish and skip L1 | yes — PASS-side miss window | A | **fix** before the tag: include the capture file in the same two-sample quiescence observation the state directory already gets (the issue's own fix shape) |
| #58 | acceptance asserts vs PYTHONOPTIMIZE | no — test infra | C | defer |
| #62 | loop-closure stage clones the full upstream | no — apparatus weight | C | defer |
| #63 | the agent-side seal has never been seen red | no — experiment apparatus | C | defer |
| #64 | secondary observations lack a committed generator | no — apparatus | C | defer |
| #65 | invariant and leg-C predicate hand-synced across spike/ | no — apparatus | C | defer |
| #86 | this audit | — | — | stays open until the fix-adjudicated issues (#5, #27, #46) land and the pre-tag re-sweep runs |
| #118 | assisted-discovery product thesis | no — product tracking, open by owner ruling | — | stays open |
| #123 | the judge cannot follow a target across execve | yes — implementing it is a trace-contract event | C | defer with the recorded reading: the single-pid exec chain is already judged under contract v10 (ADR 0018); what remains — true multi-process — refuses today (fail-closed). The hold and reopen condition are on the issue (2026-08-16), and a post-1.0 implementation bumps the contract *honestly* under surface 4's refusal promise |
| #140 | criterion 1's search half | no — process criterion | — | stays open, upstream-gated |
| #147 | outcome-map.tsv overcounts reported-upstream rows | no — evidence-page correction | — | stays open; fix is independent of any frozen surface |
| #150 | the FAIL headline counts the baseline under "crash worlds" | yes — reader-facing verdict label | B | **fix** before the tag (relabel to explored worlds; sweep acceptance greps first). Machine fields are already correct |
| #156 | `--oracle` + `--allow-unverified` accepted and inert | yes — CLI acceptance semantics | C | defer with the note said out loud: freezing means the inert acceptance is permanent — making the combo refuse after 1.0 would be a breaking change, and that trade is accepted (the report's bit is honest either way) |
| #157 | value pins cannot see a bool-vs-string type regression | no — test infra | C | defer |
| #159 | README never introduces `--shim`/`--work` outside the Example | no — docs under the cut-only order | C | awaiting the owner's call |
| #160 | onboarding-clock hardening before run 2 | no — apparatus | C | defer to run 2 |
| #161 | release glibc floor inherited, not chosen | no — release engineering, outside the five surfaces | C | worth deciding before 1.0, not contract-bound |

Twenty-six rows; ten are freeze-relevant, reading "touches" the way #86
itself reads it — the surface *or the promise it carries* (the meaning of
PASS, what a refusal says): seven sit on the declared surfaces directly,
while #26 and #150 sit on the reader-facing verdict text and #156 on flag
acceptance — constrained in practice though absent from the declaration's
enumeration. Of the four class-A members and #10, their adjacent honesty
fix, three resolve by fix or demote before the tag (#27, #46, #5) and two by
narrowing the stated promise (#39, #10) — none by leaving the PASS claim
intact over a documented hole, which is the outcome class A forbids.

## What remains before the tag

1. #27's fix, #46's fix, #5's demotion — each its own PR, with the tests #27
   specifies and equivalent pins for the other two (their issues carry fix
   shapes, not test text).
2. #150's relabel and the target-classes narrowing for #10 *and* #39 (the
   two sentences named in their rows) — small PRs.
3. Re-run the sweep, replace the snapshot file (the gate names it by date —
   update both together), update this page, re-run the gate.

#26 and #35 resolve as "document", and their rows above *are* the record —
no further page is owed.

Also retired by this audit's sweep: `src/main.zig`'s preflight refusal still
promised a machine-readable form "arriving with issue #84" — a future that
already happened without it. The text now states the standing constraint
instead of a stale promise (this PR).
