# The contract-freeze audit — v1.0 criterion 5

PRD criterion 5 freezes four surfaces at v1.0 — config format, report schema,
exit codes, replay compatibility — and issue #86 added a fifth by decision
(the MCP surface) and defined this audit: every open issue that touches a
frozen surface gets resolved *before* the freeze, because after it, a fix as
filed is a broken promise. "Defer and freeze anyway" is the one outcome this
page exists to prevent.

**Snapshot.** The classification below covers the open-issue set captured by
`gh issue list --state open` at the **pre-tag re-sweep, 2026-08-18** —
thirteen issues, committed verbatim as
`spike/freeze-audit/snapshot-2026-08-18.tsv`, replacing the original sweep's
twenty-six-issue snapshot of 2026-08-17 (the gate's `SNAPSHOT` name moved
with the file, in the same commit — the two are one trust root). Everything
resolved between the sweeps — and the four issues filed *and* resolved
between them (#164, its accidental duplicate #165, #167, #169), which a
final-state capture alone cannot see — moved to the struck rows under
"Resolved before the tag", which the gate deliberately does not count; the
filed-and-resolved set was enumerated by a closed-issue query over the
inter-sweep window, not recalled. The
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

Gate output, 2026-08-18 (re-sweep): `ok: the table covers all 13 snapshot
issues, and the gate goes red on a one-row-deleted copy` — the original
sweep's run (2026-08-17, 26 issues) measured the same shape, with the
reverse also measured once (a forged snapshot row makes it fail, naming the
row), and the re-sweep additionally measured that restoring one struck row
to active form makes the gate fail — the strike separation is load-bearing,
not typographic.

**The rule this declaration carries.** It takes effect at the v1.0 tag, not
today. Before tagging, the sweep is re-run and this page updated for any
issue opened or closed since the snapshot — **the audit is a gate, not a
ceremony performed once and aged.** The 2026-08-18 re-sweep satisfied that
rule for the tag it was aimed at; it did not retire the rule, and the
sentence saying so was briefly deleted in the re-sweep's own PR and restored
when the next two filings proved why it exists (below). The declaration's
permanent home is `docs/contract-freeze.md` — this page retires at the tag,
the promise does not.

**Filed after this snapshot** (2026-08-18, hours after it was taken, which is
the drift the rule above exists to catch): `#180` (one-command install — a
Homebrew formula, measured to need no code change) and `#181` (the "macOS has
no oracle" claim rests on `dtruss` alone; `fs_usage`, `ktrace`, OpenBSM and
Endpoint Security were never measured, and ADR 0001 still says "to be
measured"). Read against the five surfaces, neither touches one — `#180` is
release engineering, the same class as `#161`; `#181` would add capability
through channels that are already frozen and already accommodate it (the
`--oracle` flag and the `oracle_verified` field). That reading is this page's
author's, recorded so the next sweep confirms or corrects it rather than
rediscovering the issues; the formal classification is the next sweep's, and
the gate below counts neither until then.

## The declaration: what freezes at v1.0

**Moved to [`docs/contract-freeze.md`](contract-freeze.md)** (2026-08-18,
the re-sweep): this page retires at the tag, the promise does not, and a
freeze whose only home is a retired page is a freeze nobody can read. The
five surfaces — config format, report schema, exit codes, replay
compatibility, the MCP surface — live there verbatim, with their owner
decisions (#94's exit-code split declined permanently among them). PRD
criterion 5 names all five and points the same way.

## Every open issue, classified

Classes for touchers, per #86's amendment: **A** — the gap can make PASS
overclaim (prose alone cannot retire one; resolution is fix, demote to a
refusal, or narrow the stated promise); **B** — FAIL-side noise or precision
(fix or document); **C** — ergonomics and diagnostics (fix, or defer to 1.x
with a note). Class-A resolutions below are the owner's adjudication
(2026-08-17), taken with the recommendation visible before deciding.

| # | what it is | touches | class | resolution |
|---|---|---|---|---|
| #39 | libc conveniences that mutate state behind the PLT (mkstemp family) | yes — observation reach = PASS meaning | A | **narrow**: on Linux the class fails closed through the oracle (sound today). The macOS narrowing must say *this class*, not only #10's platform-binary limit: target-classes will state that on macOS libc-internal mutations are invisible with no oracle to catch them, so a macOS PASS carries only the `--allow-unverified` weaker claim the README already spells. The interpose-on-first-contact policy (PR #38) stands. **Executed 2026-08-17**: the sentence is on target-classes' Not-yet-measured section with the three measurement tiers distinguished (stdio probed on both platforms per ADR 0005, remove measured on Linux, the family itself unmeasured); the issue stays open as the family's lookout post by owner decision |
| #62 | loop-closure stage clones the full upstream | no — apparatus weight | C | defer |
| #63 | the agent-side seal has never been seen red | no — experiment apparatus | C | defer |
| #64 | secondary observations lack a committed generator | no — apparatus | C | defer |
| #65 | invariant and leg-C predicate hand-synced across spike/ | no — apparatus | C | defer |
| #86 | this audit | — | — | the pre-tag re-sweep ran 2026-08-18 (this snapshot); every fix-adjudicated issue has landed, the declaration moved to its permanent home — closes when the re-sweep's PR merges, meeting criterion 5 |
| #118 | assisted-discovery product thesis | no — product tracking, open by owner ruling | — | stays open |
| #123 | the judge cannot follow a target across execve | yes — implementing it is a trace-contract event | C | defer with the recorded reading: the single-pid exec chain is already judged under contract v10 (ADR 0018); what remains — true multi-process — refuses today (fail-closed). The hold and reopen condition are on the issue (2026-08-16), and a post-1.0 implementation bumps the contract *honestly* under surface 4's refusal promise |
| #140 | criterion 1's search half | no — process criterion | — | stays open, upstream-gated |
| #147 | outcome-map.tsv overcounts reported-upstream rows | no — evidence-page correction | — | stays open; fix is independent of any frozen surface |
| #156 | `--oracle` + `--allow-unverified` accepted and inert | yes — CLI acceptance semantics | C | defer with the note said out loud: freezing means the inert acceptance is permanent — making the combo refuse after 1.0 would be a breaking change, and that trade is accepted (the report's bit is honest either way) |
| #160 | onboarding-clock hardening before run 2 | no — apparatus | C | defer to run 2 |
| #161 | release glibc floor inherited, not chosen | no — release engineering, outside the five surfaces | C | worth deciding before 1.0, not contract-bound |

Thirteen active rows at the re-sweep (twenty-six at the original sweep;
seventeen struck rows below — thirteen from the original snapshot, four
filed and resolved between the sweeps). Every class-A adjudication executed
before the tag: fix (#46, #164, #169), demote (#5), measured already-fixed
(#27), narrow (#39 — executed 2026-08-17, its row *active* because the
issue stays open as the mkstemp family's lookout post by owner decision);
the A-adjacent #10 narrowed with its diagnostic clause and CI pin, and the
class-B #150 fixed on both verdict headlines — none resolved by leaving
the PASS claim intact over a documented hole, which is the outcome class A
forbids. What stays open is class C and process apparatus (#62–#65, #123,
#147, #160, #161), the deliberate deferrals with their trades recorded
(#39's lookout post, #156's flag-acceptance permanence), the
product-thesis and process trackers (#118, #140), and
this audit itself (#86, which closes when the re-sweep's PR merges).

## Resolved before the tag

Every row below was an open issue in a sweep's snapshot (or was filed and
resolved between the sweeps — #164, its duplicate #165, #167, #169 —
enumerated by a closed-issue query over the window, since a final-state
capture cannot see an issue that opened and closed inside it) and closed
before the tag; the struck rows keep their adjudication history. The gate
counts active rows only — a struck row's leading cell no longer matches its
anchor — so this section is record, not obligation; that the strikes are
genuine (each issue really closed) is commit review's job, stated here the
same way the snapshot's own trust is.

| issue | what it says | touches a frozen surface? | class | resolution |
|---|---|---|---|---|
| ~~#5~~ | restore drops FIFOs/sockets/devices; worlds differ from the recorded tree (symlinks fixed in #122) | yes — verdict soundness | A | **demote**: detect a non-regular, non-symlink entry at snapshot time and refuse (UNKNOWN) rather than explore a tree that cannot be reproduced. Fix lands before the tag. **Landed 2026-08-17**: `unsupported_state_entry` fires at all three snapshots (initial, final, crashed — the last catching entries no syscall witness saw born), and the demotion's own review first forced the entrance repair: the `DT_UNKNOWN` fallback used to probe by opening, which hangs on a FIFO and misclassifies sockets and devices — classification is by `statx`/`fstatat` now, no open, no follow |
| ~~#6~~ | the oracle reads any quoted string on a strace line as a path; a target that *prints* a state path draws a false refusal | no — internal parsing precision, fails closed, fix is non-breaking | — | ~~stays open; fixable in any 1.x~~ **Closed 2026-08-18, measured already-fixed**: the issue predates ADR 0006 (2026-08-11), whose typed resolver names this false-positive verbatim in its Context and closed it — a classified `write` is an fd syscall, scoped from its descriptor annotation only, and the named unit pin exists ("a state-directory string inside a write buffer is not scope"; mutation-checked once with attribution fixed by `--test-filter`). The close is scoped to the named case: the conservative whole-line net remains for *unclassified* syscalls and only ever refuses — deliberate fail-closed residue |
| ~~#10~~ | macOS Apple platform binaries can never be observed; the docs imply a narrower limit | yes — the stated promise | A-adjacent | **narrow**: `docs/target-classes.md` states plainly that a macOS target must be self-built or self-installed, never an Apple-shipped binary. The README stays under its cut-only order. **Landed 2026-08-18, wider than adjudicated here by owner decision**: the report's macOS build also names an Apple-shipped platform binary as *one possible cause* on the `no_shim_marker` detail line — never the cause; the review killed the attributing form, since the marker proves only that `shim_ready` never appeared — with the refusal shape (exit 2, token, clause, the JSON `message` contained verbatim in the text) pinned permanently in the macOS CI job, each check predicate seen red once. The Linux wording is byte-identical |
| ~~#12~~ | the omamori dogfood cannot be agent-driven | no — internal tooling | C | ~~defer to 1.x~~ **Closed 2026-08-18, owner decision**: the by-design account was already on the record — PRD's v0.4 status carries the full account (the guards fire for a human at a terminal exactly as for an agent; measuring one would need break-glass, which removes the defence under test), and DESIGN says "not measured either way". Closed as documented, not as fixed; the audience-assumption generalisation went to `docs/scouting.md` as one sentence |
| ~~#13~~ | stdio (fopen/fwrite) invisible to the shim | **stale** — fixed by ADR 0005 (flush-granularity observation), pinned by acceptance check 2u | — | **close as fixed**; the unmeasured reach note (Go, raw syscalls) already lives on the target-classes page |
| ~~#26~~ | target-chosen paths reach the text report unescaped | yes — report surface (text) | B | ~~document~~ **Corrected 2026-08-17, owner decision**: fixed ahead of the adjudicated minimum — the forged line was demonstrated on the pre-fix binary, the three target-chosen operands now reach the text defanged while the JSON keeps the exact bytes, and the acceptance suite pins both sides. Closes with the fix's merge |
| ~~#27~~ | standard-form L0 misses a file replaced by a directory when pre or post content is empty — a real false-PASS window | yes — the meaning of PASS | A | ~~fix before the tag~~ **Corrected 2026-08-17, measured**: the issue predates #122, whose (kind, content) pair rule already closed the named window **for pairs that enter the plan** — the issue's own scenario, both empty sides, now lands as one unit pin per case through the real classify+judge path, and a kind-blind mutation reds each pin test individually while sparing the non-empty control. Closes as measured when the pin change merges. The measurement also found the adjacent gap *outside* the plan — the dir-to-dir pair exclusion — filed as #164 and fixed in the same change; #164 joins this table at the pre-tag re-sweep per the snapshot rule |
| ~~#35~~ | L0 flags git's COMMIT_EDITMSG scratch file | yes — FAIL-side precision | B | document as a named precision limit on non-durable files — **executed 2026-08-17**: the scratch-file pattern joined the checker cookbook's failure-patterns list with the measured run cited. Closes as documented with that change's merge |
| ~~#46~~ | no quiescence observation on the stdout capture under a tolerated boundary — a marker could silently vanish and skip L1 | yes — PASS-side miss window | A | **fix** before the tag: include the capture file in the same two-sample quiescence observation the state directory already gets (the issue's own fix shape). **Landed 2026-08-17** (PR #170): the capture joins the two-sample observation on both the recording and every world, arming extends to world-local boundary evidence, and the one open follow-on — whether a world-only boundary should refuse outright — is #169, deliberately out of this audit's scope because deciding it changes verdicts |
| ~~#58~~ | acceptance asserts vs PYTHONOPTIMIZE | no — test infra | C | ~~defer~~ **Corrected 2026-08-17, owner decision**: fixed ahead of the adjudicated deferral — every judgment `assert` across both acceptance suites and the quickstart workflow replaced by explicit exits, the assert-version hole demonstrated once on falsified input, and both suites run entirely green under `PYTHONOPTIMIZE=1`. Closes with the fix's merge |
| ~~#150~~ | the FAIL headline counts the baseline under "crash worlds" | yes — reader-facing verdict label | B | **fix** before the tag (relabel to explored worlds; sweep acceptance greps first). Machine fields are already correct. **Landed 2026-08-18**, wider than filed: the PASS headline carried the same mislabel (the issue never named it; the plan review did) and both verdicts now say explored worlds, with the printed numbers pinned against the same run's JSON `violations`/`explored` — a wording-only pin would have passed a wrongly-changed denominator |
| ~~#157~~ | value pins cannot see a bool-vs-string type regression | no — test infra | C | ~~defer~~ **Corrected 2026-08-18, owner decision**: fixed ahead of the adjudicated deferral — the seven oracle_verified pins go through one typed predicate (`type is bool` with the value), self-falsified on every call against an in-memory string-"True" document through the same predicate. Closes with the fix's merge |
| ~~#159~~ | README never introduces `--shim`/`--work` outside the Example | no — docs under the cut-only order | C | ~~awaiting the owner's call~~ **Resolved 2026-08-18, owner decision**: a minimal Usage addition — `--shim` and `--work` introduced in the README's flag list (PR #177); criterion 6's evidence stays the pre-change README's run, deliberately not re-measured |
| ~~#164~~ | a dir-to-dir pair is excluded from judgment entirely | yes — adjacent to #27's false-PASS window | A | **Fixed 2026-08-17, by the same measurement that closed #27** (filed between the sweeps; #27's row promised this row would join at the re-sweep): the pair-rule exclusion #27's measurement surfaced *outside* the plan, closed in the same change with per-case unit pins |
| ~~#165~~ | (accidental duplicate of #164) | — | — | **Closed 2026-08-17 as a duplicate**: a shell precedence slip in the filing command created the same issue twice; #164 is canonical |
| ~~#167~~ | the text defang stops at 0x7f; raw C1 bytes pass through | no — display hardening, outside the five surfaces | C-shaped | **Fixed 2026-08-18 ahead of any deferral, owner decision** (filed after the 08-17 snapshot; classified at the re-sweep): one UTF-8-aware classifier behind both text-side predicates — plan review found the second, `sanitizeForReport` — C1 defanged in both encodings, invalid bytes one at a time, real multi-byte sequences spared, both routes pinned with a byte-wise mutation seen red (PR #177) |
| ~~#169~~ | a world-only process boundary is tolerated with no account of that world | yes — what a verdict means over a boundary nobody accounted for | A | **Fixed 2026-08-18, owner decision** (filed after the 08-17 snapshot; classified at the re-sweep): refuses under `boundary_without_oracle` — the issue's own per-world analog, so the schema's closed set does not move; the world-story `processes` account precedes the refusal; the existing tolerate check inverted as the red/green pair; ADR 0002 superseded in part, its knowingly-open recording-crossed window now stated to cover the whole remaining exposure (PR #176) |

## What remains before the tag

1. ~~The adjudicated fixes~~ — done: #46's observation and #5's demotion both
   landed 2026-08-17 (#27 left this list the same day, measured already-fixed;
   each row above carries its record).
2. ~~The target-classes narrowing for #10~~ — done: landed 2026-08-18, wider
   than the docs-only adjudication (the report's macOS clause and a CI pin
   came with it; #39's narrowing executed 2026-08-17, #150's relabel landed
   2026-08-18 on both verdict headlines — each row above carries its record).
3. ~~Re-run the sweep~~ — done 2026-08-18: snapshot replaced (13 issues,
   gate path moved in the same commit), the four issues filed and resolved
   between the sweeps accounted (#169 class A, fixed — the world-only
   boundary refusal; #167, fixed — the UTF-8 defang; #164, fixed 2026-08-17
   with #27's measurement; #165, its duplicate) with #159's held call
   resolved alongside, resolved rows struck, gate re-run green
   with the strike separation seen red once.

Nothing on this list remains, and criterion 5 is met — #86 closed with the
re-sweep (2026-08-18). One standing obligation is not on the list and never
leaves it: the rule above. Whatever is filed between now and the tag gets
swept and classified before the tag, however many times that takes; two such
filings already exist (`#180`, `#181`, noted at the top). "Criterion 5 is
met" is a statement about the audit that ran, not a promise that the tracker
stopped moving. The declaration's permanent home is
`docs/contract-freeze.md` — the freeze survives this page's retirement at
the tag.

#26 and #35 resolve as "document", and their rows above *are* the record —
no further page is owed.

Also retired by this audit's sweep: `src/main.zig`'s preflight refusal still
promised a machine-readable form "arriving with issue #84" — a future that
already happened without it. The text now states the standing constraint
instead of a stale promise (this PR).
