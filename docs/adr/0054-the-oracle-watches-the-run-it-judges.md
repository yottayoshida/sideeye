# ADR 0054 — The oracle watches the run it judges, in every observation mode

- **Status:** Accepted (2026-09-08)
- **Supersedes:** ADR 0052 decision 4 ("the two witnesses come from two runs — and the
  claim gets its own name"); withdraws ADR 0053 §4 ("`--observe syscalls` is outside the
  slice"). Amendments on both pages point here.
- **Scope:** which execution the completeness oracle observes, the `oracle_verified`
  channel, and the composition of the two improvements shipped in contracts v14 and v15.
  The trace contract itself does not move — v15 stays v15, because neither the trace nor
  the shim/engine protocol changes.

## Context

`--observe syscalls` (ADR 0052) counts the write family at the kernel boundary, through a
seccomp filter that answers `SECCOMP_RET_TRAP` and a `SIGSYS` handler that counts and then
re-issues the call. It is the only way to see a write libc issues from inside itself.

ADR 0052 decision 4 declined to attach an oracle to a run in that mode, and measured the
reason: a trapped write is not executed by the kernel, so strace sees each one twice — once
refused, once re-issued — and `oracle.compare` is positional, so every oracle-attached run
would refuse `oracle_missed_operation`. The oracle was therefore pointed at a *separate,
untrapped* run of the same operation, and the weaker claim that earns was reported as
`oracle_verified_across_runs`.

Two things followed from that arrangement, and the second was not visible until v15:

1. The report's strongest field was unreachable in this mode, and the account had to
   explain that the two witnesses were of two executions.
2. **The v15 multi-process slice (ADR 0053) could not be used with it.** That slice admits
   a writing child as a crash point when both witnesses name the same writers *of the same
   run*; a mode whose oracle watched a different run has no second witness for the run the
   trace came from, so ADR 0053 §4 refused the whole class there. `lbdb` is the target that
   needs both — its writing child flushes buffered stdout at `exit()`, which only the
   syscall boundary sees, and it is a child, which only the v15 slice admits — so it was
   refused whichever improvement was selected.

## Decision

**1. The oracle watches the run whose trace is judged, in every mode.** The leading
untrapped run and the state restore between the two are removed. `--observe syscalls` runs
the operation once for the recording, like every other mode.

**2. A refused call is retracted when its refusal is read.** The reader appends an in-scope
write as it always has. When it then reads `--- SIGSYS {... si_code=SYS_SECCOMP ...} ---`
for that process, it removes the entry it last appended for it. Two properties make this
enough, and both were measured (`spike/followup-trapwitness/`):

- strace prints the signal without being asked. `-e trace=` filters syscalls, not signals,
  so the flags the engine already passes carry it. No flag changes.
- Between a refused call and its signal, no other line from the *same* process can appear:
  it is stopped waiting for the delivery. Its own `<... write resumed>` may, and that form
  has no name for the reader's syscall-name test to return, so it does not close the
  window. Another process's lines may appear freely, which is why the window is per
  process and why the removal is by index rather than by popping the last entry.

`si_code` is the discriminator rather than `si_syscall`, because the entry a refusal
retracts was already restricted to the trapped family when it was appended, and no filter
in this tool traps anything else. An older strace that spells `si_syscall` as a bare number
is therefore read the same way.

Any other line from the process closes the window. Without that, a write to a file
**outside** the judged state — trapped too, since the filter keys on the syscall number and
not on the path — would raise a signal that retracted an unrelated earlier operation. The
first draft of the test for this pinned a state the tool cannot produce and passed with the
window-closing line deleted; the mutation run is what said so.

**3. `oracle_verified_across_runs` is removed, not deprecated.** The run that produced the
weaker claim does not exist, so a field named for it would name nothing.
`spike/check-report-schema.py` fails a field the page documents and the code never
generates, in that direction on purpose, so leaving the row standing was not available.
This is a break of the freeze's surface 2 and is recorded as one in
`docs/contract-freeze.md` — the third, by owner ruling, and the first that is a *removal*.
A consumer gating on `verdict == "PASS" && oracle_verified` now counts syscalls-mode runs
it used to exclude, which is a strengthening; what changed is the run, not the gate.

**4. ADR 0053 §4 is withdrawn.** `childrenMayBeJudged` no longer takes the observation
mode. Its two conditions are asked of a syscalls-mode run the way they are asked of any
other, because that run now has the second witness they consult.

**5. The contract version does not move.** Neither the trace format nor the shim/engine
protocol changes; what changes is which run the engine attaches the oracle to, and how the
capture is read. `oracle_verified`'s documented meaning — the comparison completed and
agreed — is unchanged.

What this mode gains is **not** that `oracle_verified` is always set here. It is that the
mode stops deciding the question: a completed and agreeing comparison is read by the same
rules as in every other mode, so it earns `oracle_verified` on a run whose crash points are
all the subject's, and `oracle_verified_subject_only` on one whose writing children were
admitted (ADR 0053). `lbdb`, the target this change was aimed at, is the second kind — it
reaches a verdict with `oracle_verified_subject_only`, which is the strongest claim its own
shape allows. A draft of this ADR said the mode "earns `oracle_verified`" flatly, and the
measurement committed beside it falsified that in one line.

## Alternatives considered

- **Pair each refusal with its re-issue, by lookahead.** Recognise the second line as the
  first one's re-issue and count the pair once. Rejected: it needs a delayed commit for
  every appended write, a flush at end of input, and index bookkeeping across three aligned
  lists — and it needs a rule for "is this a re-issue" that can misread an unrelated write
  to the same descriptor. The retraction needs none of that: nothing has to be recognised
  as a re-issue.
- **Compare the two accounts as sets rather than positionally.** The doubling disappears
  and so does the order, and `oracle_missed_operation` could no longer name *which*
  operation diverged. Rejected: the divergence message is the product here.
- **Ask strace not to print signals (`-e signal=none`).** Throws away the only material
  that distinguishes the refused call from the one that ran.
- **Recognise the handler by its own footprint** — its `readlinkat` on `/proc/self/fd/N`
  and its record write — and pair on that. Closes the misreading the lookahead has, but
  only for descriptors the shim records; the rule becomes two rules. Moot once the
  retraction removed the pairing question.
- **Keep the field and never set it.** Not available: the schema check fails a documented
  field that is never generated, and a field that can never be true is a claim with nothing
  behind it.

## Consequences

- `--observe syscalls` under an oracle earns `oracle_verified`, and the `oracle` account
  discloses how the capture was read on every run in that mode.
- The **recording phase** runs the operation once, not twice. The capture the oracle reads
  grows about 1.6x for the same operation under the same oracle flags — 158 lines against
  98, both committed under `spike/followup-trapwitness/artifacts/`. **No speedup is
  claimed:** end to end the two engines are indistinguishable on the toy this was measured
  on (medians of seven runs, 43 ms against 44 ms), because the run that went away is one
  execution of a millisecond-scale operation while both engines still explore fifteen
  worlds. A target whose operation is expensive is where a difference would show, and none
  was timed.
- A divergence in this mode is a disagreement about one execution, so `oracle_saw_phantom`
  stops suggesting the target failed to repeat and returns to naming a defect in this tool.
  What the message adds instead is this mode's own two readings: a refusal the capture did
  not carry leaves one operation too many, a retraction that fired on an entry that ran
  leaves one too few.
- `--twice` in this mode now measures the same two runs every other mode does. The
  acceptance leg that guarded the old three-run arrangement is inverted rather than
  deleted: a measured gap in the 2000s there means a third run has reappeared.
- The two improvements compose. What that buys is recorded per target in
  `docs/target-classes.md`.
- **The retraction is applied to every capture, not only this mode's.** `parse` is given
  text and does not take the observation mode, so a target that installs its own
  `SECCOMP_RET_TRAP` filter has its refused calls retracted under `--observe wrappers` as
  well. That is the correct reading of the line — a refused call did not run, whoever
  refused it, and counting it would place a crash point where no state changed — and
  gating it on the mode would make the default mode wrong in exactly that case. The effect
  is that such a target can reach a verdict in the default mode where it used to refuse
  `oracle_missed_operation`; `docs/report-schema.md` says so rather than leaving it to be
  found. A target with its own filter or handler is outside what this mode models either
  way, which is the last item on that page's list.
- What this mode still does not see is unchanged and is listed in `docs/report-schema.md`:
  raw `copy_file_range`/`sendfile`, `pwritev2` (refused, not counted), a 32-bit compat ABI,
  a target that issues a trapped call already carrying the re-issue marker, and a target
  that installs its own `SIGSYS` handler or seccomp filter.
