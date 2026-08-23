# himalaya, cohort 4 target 1: the property, and what is declared before the engine runs

## P1 — the property

Crash anywhere inside `himalaya maildir messages copy`, and the store holds
either the old message set, or the old set plus the **complete** copy of the
message in the target folder, with himalaya's own reader agreeing about
which. Nothing in between: no message that exists but is empty, no message
that exists but is cut, no message that has lost the flags it was copied
with.

## Why this arm, and where the interior is

io-maildir gives `message save` a tmp stage and a rename, and `message move`
and the flag commands a single rename. Those are the papis shape: one atomic
mutation, nothing to crash inside. **`messages copy` does not stage.** It
mints the destination name, builds the final path, and fills the file there
(`entry/copy.rs`; the I/O is `fs::copy` at `client.rs:227`). The accepted
probe counted the interior at **two engine-reachable kill points, one open
and one write** (`../probes/himalaya.txt`, condition 9).

So the shape of a torn state is known in advance: a message file that exists
at its final path in the target folder, with fewer bytes than the source, or
none at all.

## What the trials measured before the checker was written

`pre-define-trials.txt`, engine-free:

- **The reader does not write.** Five states — healthy, zero-length,
  cut-mid-headers, absent, and a `message read` — with every path, size and
  checksum in the store snapshotted around each invocation. Nothing mutated.
  papis's reader had to run last because it minted and persisted an id; this
  one does not, and the checker says so rather than inheriting the rule.
- **The reader cannot tell a torn copy from a whole one.** A zero-length
  message lists as an ordinary envelope: one row, `0 B`, blank subject, from
  and date, rc 0. A message cut mid-headers also lists as one row. Only
  `message read` fails on the zero-length one (rc 1). So the byte assertion
  is the leg that catches the damage, and leg R runs beside it, not instead.
- **There is no documented recovery to run first.** The command surface has
  no doctor, repair, check, verify or fsck, and the maildir subtree offers
  create, rename, delete, list, messages and flags. Nothing claims to repair
  a store, so nothing is run before the assert — measured, not assumed.

## Declared world readings, before the engine runs

Stated here so the run can contradict them:

1. **Two crash points plus the un-killed baseline**, matching the probe's
   interior count. More would mean the define reaches writes the probe did
   not see; fewer would mean the seccomp profile changed the write path.
2. **Single process, `oracle_verified: true`.** The probe measured zero
   threads on this path and every in-root mutation interposable.
3. **A FAIL is expected, not a PASS**, and specifically through **leg D**:
   the kill between the create and the fill should leave a message file at
   its final path with the wrong number of bytes. If the run comes back
   PASS, the interior is not where the probe counted it.
4. **The report should carry `checker_earliest`** (#231, ADR 0020): the
   violating world's violation includes the declared checker, which is what
   this cohort's claim rule requires of a candidate. An L0-only FAIL — the
   engine's built-in atomicity invariant firing while the checker stays
   green — would be a precision-limit observation and not a candidate.

## What a finding here would mean, stated before it exists

A torn copy is not only a file with missing bytes. The trials measured what
the tool shows for one: an envelope in the folder listing, `0 B`, which a
person reading their mail sees as a message that is simply there. The
recovery path outside the tool is the other side of the sync — and that is
the condition the freeze's Reporting section says must be measured before
any report is drafted, not assumed from the shape of the crash.
