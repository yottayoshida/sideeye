# 0043 — A define names its scratch paths, and the judge leaves them alone

Status: Accepted (2026-09-03)

Closes #261. The eighth key of `[define]` (`apparatus`, ADR 0041, was the seventh), and the
sixth time DESIGN.md §12's sentence — *if Define ever needs more than this, that is movement
toward the kill criteria in §18, and we should notice* — is faced on the record. This one
reverses a ruling: `docs/checker-cookbook.md` closed #35 with "L0 exempts no file *by its
role*", written when a define had no place to say a role. Now it has one, and the cost of
saying it is paid where a reader can see it.

## Context

The built-in atomicity invariant judges every path the recording had before and after the
operation: the crashed state must hold the old identity or the new one. It cannot tell a
durable path from a scratch one, and four times a scratch path decided a verdict:

- git's `COMMIT_EDITMSG` (#35): opened with truncation before the message is written, torn
  to empty in that window. Not a git bug — the next commit rewrites it and nothing reads a
  torn one. Closed as a precision limit, with the recipe "a checker carrying the real
  integrity claim": `git fsck --connectivity-only` accepted all thirty-four worlds.
- buku (the assisted cohort, withdrawn 2026-08-15): the L0 hybrid was a byte observation of a
  store whose journal recovers the file, and the recorded evidence was the falsification
  gate's own output (`spike/assisted/RESULTS.md`).
- Borg's client cache (cohort 2): the define relocated `BORG_BASE_DIR` into the judged root
  and all three L0 violations landed in that cache's in-place rewrite.
- Mercurial's dirstate (cohort 2): FAIL 73 of 107 worlds, every violation L0-only, while the
  documented contract held in all 107 and the checker's transcript carried zero leg failures;
  claimed as nothing (`docs/target-classes.md`).

And poetry stays FAIL 2/5, an L0-only precision limit under the frozen claim rule. The
checker recipe is right about knowledge — the checker is the only thing that can say the
state is *correct* — and wrong about the verdict: a checker cannot subtract from L0, which
fires whether or not a checker exists, so the report's headline and the world count are
decided by files nobody depends on. `--state` cannot be narrowed around `.git/COMMIT_EDITMSG`
without losing the repository it sits in; moving the path outside the judged root needs the
target's cooperation, and Borg showed the relocation running the other way.

The owner chose on 2026-09-03, from two shapes (a key that names scratch paths; document the
limit and close), the key.

## Decision

`[define] scratch` is an array of paths relative to `state`, each naming the path itself and
everything beneath it (`rel == p`, or `rel` begins with `p` followed by `/`; the snapshot
spells a directory as `foo`, never `foo/`, so a subtree-only form would miss the directory's
own pair, the pair #164 made enter the plan). `--scratch PATH` is the flag form, repeatable,
and joins the define-surface flags that are exclusive with `--config` (ADR 0007) and refused
by `replay`, which takes its define from the case. One grammar for both, in `config.zig`:
a leading `/`, a `.` or `..` segment, an empty segment and a double quote are refused;
trailing slashes are dropped, so the spelling the report carries is the one the judge
matches. An empty array is refused; leave the key out to declare nothing.

**What the judge does.** A declared path is judged by neither built-in invariant, in no
world and on no side of the pair: not its bytes, not its presence, whether the recording had
it before, after, or both. Mechanically, a pair matching the declaration never enters the L0
plan (`engine.classifyWith`), so `judgeL0` and the plan-walking loop of `judgeL1` cannot
reach it; the two `judgeL1` loops that walk the snapshots rather than the plan — the
post-only paths a success claim requires to exist, the pre-only paths it requires to be gone
— ask the declaration themselves. The baseline world is judged by the same plan, so a
declared path whose bytes differ between two clean runs no longer refuses the run as
`baseline_violates_invariant`. The plan carried a tag on the pair instead, and review found
the hazard: a tag has to be honoured before `crashed.find` in both judges, and a skip one
line too late reports the path as `missing` — asking after a presence the declaration said
not to ask about. Left out of the plan, there is no line to place.

**What the report says.** The declaration verbatim in `scratch`, present only when the
define declared something (the presence rule `apparatus` follows). The `atomicity` line
gains "; K path(s) matched by scratch, not judged (declared: …)", where K is the number of
recorded paths, before or after, the declaration matched — so a reader can tell a
declaration that reached something from one that named nothing the recording had, and a
define that declared everything reads "0 path(s) judged pre-or-post; N matched by scratch".
`not tested` gains "declared scratch paths (neither bytes nor presence judged)" whenever
the define declared any. `preflight --twice` honours the same declaration: a declared path
is left out of the comparison and the report says so, because README points at `--twice`
as the byte-repeatability wall's measurement, and a wall the exploration no longer hits
must not still be reported by the preflight.

**What the case carries.** The declaration decides verdicts, so a replay without it would
judge a different question; the saved case carries it, as version 5. Version and shape
travel together (ADR 0014, 0019), and a fifth version holds two independent optional
fields, `cwd` and `scratch`, where the fourth held one — the gate that made version 4
honest (`case_version == 4 and cwd == null` refuses) cannot be copied, because a v5 file
without `cwd` is not malformed. So from version 5 a case spells both keys the top of the ladder
introduced: `cwd` as JSON `null` when the define declared none, `scratch` as a non-empty array
(`setup`, `check` and `marker` stay as they were: written when declared).
The reader parses a v5 file a second time as raw JSON and requires the `cwd` key to be
present and `scratch` to be non-empty; a file below 5 carrying `scratch`, or a v5 file
missing either, refuses as malformed rather than replaying under a guessed contract.
`writeCase` picks 5 when anything was declared scratch, 4 when only `cwd` was, and the
older versions as before, so a define that declares nothing keeps producing the case it
always did.

**What scratch does not silence.** Only L0 and L1. `state_changed_unaccounted` (#405), a
state that changed with no operation recorded, an unsupported entry kind, a file over the
snapshot ceiling, and `state_not_quiescent` — two samples of the tree taken back to back
that disagree, a scratch file still being written included: each still refuses on a
declared path, because each is about whether the engine observed what happened, not about
whether the path is durable.

## Answering the test `cwd` and `apparatus` passed

The test is "no other way to say it". A checker cannot say it: a checker adds knowledge and
cannot subtract from L0. `--state` cannot say it: the directory is the unit, and the scratch
path sits inside the thing being judged. `not tested` cannot say it: the engine writes that
line, not the define. Moving the path out needs the target's cooperation. Scratch is the
only place, and what it says is not the target's behaviour — the shape §12 refuses — but the
range of the question the define asks: `--state` fixes that range at directory granularity,
and `scratch` narrows it to path granularity. What it buys is the cleanliness of the
verdict, not knowledge; the cookbook's git measurement stands — the checker is still the
only thing that says the repository is intact — and the ruling that L0 exempts no file by
its role is reversed here because the reason for it was the absence of a place to say the
role.

The cost of the freedom to hide is paid in the open: the declaration is in the report and in
the case, the count says what it reached, and `not tested` names it beside power loss.

## Alternatives considered

- **An L1 durability marker (existence only).** The issue's second candidate: judge the
  path's presence but not its bytes. Refused: git deletes `COMMIT_EDITMSG` and creates it
  again, so the delete-then-create window would report a false `missing` on exactly the file
  the key exists for.
- **The engine guesses.** A path rewritten with different bytes between two clean runs is
  scratch. Refused: that is also what a clock, a random id and an inode-keyed cache look
  like, and #199 chose to name the path and refuse rather than guess.
- **No key; document and close.** Refused by the owner: the verdict stays decided by files
  nobody depends on, and every cohort pays again.
- **Not in the case, as `apparatus` chose.** Refused: apparatus does not decide verdicts and
  its safety net is #199's refusal; scratch decides verdicts and has no net.
- **Two spellings, `foo` for the path and `foo/` for its subtree.** The first draft. Refused
  in review: the directory's own pair is in the plan since #164, and the subtree form would
  have left it judged.
- **Copy the v4 gate for v5.** Refused in review: it holds only while the newest optional
  field sits alone at the top of the ladder.

## Consequences

- Config format, report schema and replay compatibility each gain one additive item:
  the key, the field, the version. `docs/contract-freeze.md` names all three.
- A define can hide a path. The report and the case say which, and the count says how much
  of the recording that was; a reviewer who sees "0 path(s) judged pre-or-post" beside a
  PASS knows what the PASS is about.
- The checker is unchanged in what it is for. A target with scratch files still needs a
  checker to say its state is correct; scratch only stops L0 and L1 from saying it is not.
- The sealed cohort defines are not revisited. The cookbook's #35 paragraph records the
  reversal beside the measurement it keeps.
- The MCP text summary does not gain a `scratch` line. `apparatus` has one because a device
  that reached the child is part of what the run *was*; the declaration's cost is carried by
  `structuredContent`, which is the whole report — `scratch`, the `l0` line with its count,
  `not_tested` — and is what an agent branches on. A summary line is an additive change to
  surface 5 if a reader of the text alone turns out to need it; it is not made here.
