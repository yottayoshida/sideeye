# himalaya-r2: FAIL through the declared checker, reproduced

## The verdict

**FAIL, 1 of 3 explored worlds, `oracle_verified: true`, single
process.** Two runs, and the report fields that carry a judgement are
identical across both: verdict, exit code, oracle verification, world
count, violation count, process count, the crash point, and the violated
invariant. The eight fields that differ are the minted filename, which
the checker is deliberately name-agnostic about, and the per-run work
paths.

The violated invariant is **the checker (L2)**, not the engine's
built-in atomicity invariant, and the report carries
**`checker_earliest`** (#231, ADR 0020). Under this cohort's frozen
claim rule that is what a criterion-1 candidate is:

> A criterion-1 candidate is a run whose `checker_earliest` exhibit
> exists ... and the exhibit named there is the claim's exhibit. An
> L0-only FAIL is a precision-limit observation, recorded and never
> claimed.

The exhibit replays: `run1/replay-transcript.txt`, "the case
reproduced".

## What the crash leaves

The kill lands at crash point 2 of 2, **after the destination is opened
and before anything is written to it**:

    after  open(<store>/Archive/cur/<minted>:2,S)
    before write(<store>/Archive/cur/<minted>:2,S)

and the checker fails through leg D:

    leg D: the copy is present but its bytes are not the source's
           (0 bytes on disk against 307 in the source)

A message file exists at its final path in the target folder with no
content in it. That is the window `proposals.md` named before the engine
ran, and it is there because `messages copy` is the one io-maildir arm
that does not stage: it mints the name, builds the final path, and fills
the file in place.

## What the declaration predicted, and what the run did

`proposals.md` was committed before the engine touched the target. Every
declared reading held:

| Declared | Measured |
|---|---|
| two crash points plus the un-killed baseline | 3 worlds, crash points 2 + 1 baseline |
| single process, `oracle_verified: true` | both, in each run |
| a FAIL through leg D, not a PASS | FAIL, leg D, 0 bytes against 307 |
| the report carries `checker_earliest` | present, invariant "the checker (L2)" |

Nothing in the declaration was adjusted after the fact. The one thing it
did not predict is in the metadata line, disclosed and unjudged: one
`fchmod` outside the judged state (#121, #190).

## What is not claimed here

- **No upstream contact.** Each report is its own owner-approved gate,
  and nothing here authorises contact. The freeze's other precondition,
  the outside-the-tool recovery paths, **is now measured**
  (`external-recovery.txt`, seven legs). Every sentence below is scoped
  to the one account configuration measured: a maildir account with no
  remote, on this build.

  - **Two recovery paths work, and both need the user to notice first.**
    The source is byte-identical after the crash, so the copy can simply
    be repeated. The repeat does not remove the empty entry: the folder
    afterwards holds both and the tool lists both as messages. The empty
    entry can also be moved out by the tool's own delete, once the
    account names a trash mailbox and that mailbox exists. It lands in
    Trash still at 0 bytes; emptying the trash was not measured.
  - **Nothing measured offers to notice.** Of 216 command names (the
    tree's depth measured, not assumed; the strict walk had 0 failed
    `--help` invocations, so no subtree was silently treated as a leaf)
    two are repair-shaped and neither is about stored mail: `account
    check` validates the account and reports `maildir: OK` over the
    damaged store, and `gmail settings send-as verify` is alias
    ownership. No name in the surface is a sync. This is a claim about
    names: commands that *read* stored mail plainly exist, and
    `envelope list` is how the empty entry gets displayed as an ordinary
    message in the first place. The one independent reader tried,
    python's `mailbox.Maildir`, enumerates it as an ordinary message as
    well.
  - **Re-fetching from a server cannot restore the target-folder
    entry**, because that entry is never sent anywhere while it is being
    created: the operation makes no call of the traced `%network` class,
    against a positive control on the same filter and the same counting
    expression. That is about the entry, not the content. The content
    may well exist on a server, and it certainly still exists in the
    source folder, which is the honest limit of this finding's severity.
  - **Two things measured against my own framing.** `message delete`
    first refused on the empty entry, which read like a second defect;
    the control refuses in the same words on a healthy message in the
    same folder under the same config, so it is a property of an account
    with no trash mailbox and is not reported as part of this finding.
    And the first draft of the network leg counted a hand-written list
    of syscall names, which measures "none of the names I thought of"
    rather than none: the positive control catches `getsockname` and
    `getpeername`, which that list did not have.
  - **Now measured — and it moves the severity in both directions**
    (`outward-reach.txt`, #272). The four things left open above were
    measured on 2026-08-23 in two images: the damage produced by the
    cohort-4 image untouched, the syncer and readers in a separate image
    that never contains the target, so no package install could disturb
    the shared libraries the pinned binary resolves against.
    - **The empty message travels, and a real server keeps it.** isync
      1.5.1 loads the damaged folder as two messages, not one, and pushes
      both. Synced alone from a clean near side — so the far side's count
      is about that entry and nothing else — the empty entry produces one
      far-side message whose entire content is mbsync's own `X-TUID`
      header. Pushed to dovecot 2.4.1 over IMAP, an independent client
      asking the server sees **two messages in INBOX**, one of them
      `RFC822.SIZE=22` with no subject — and with that identification
      removed as well, by pushing the empty entry alone into a mailbox of
      its own: the server reports one message there, and **a clean second
      store pulling that mailbox receives one file of 21 bytes**. That is
      the shape the freeze calls the strongest form, measured end to end:
      the external recovery path carries the damage outward, a real server
      keeps it, and another device downloads it. The report's statement
      that the entry is never sent anywhere is about the copy itself and
      remains true; what happens afterwards is this. Scope: one syncer at
      one version, one server at one version, one configuration.
    - **One reader flags it, one does not.** `notmuch new` (0.39) prints
      `Ignoring non-mail file` naming the entry and indexes one message of
      three files. A planted control — malformed but *not* empty — draws
      the same refusal in the same run, so the complaint is **not specific
      to emptiness**; what it establishes is that notmuch separates
      parseable from unparseable and this entry falls on the unparseable
      side. It does not characterise every unparseable file, and it is a
      detection path without being a diagnosis. Python's `mailbox.Maildir`
      enumerates all three as messages, which is what the report says and
      stays true.
    - **The tool can finish the cleanup after all.** `message delete`
      relocates the entry to Trash, as R5 measured; a second
      `message delete` against the Trash copy reports
      `Successfully deleted 1 message(s) from the trash` and the folder is
      empty. So the route is the delete command twice, on an account whose
      trash mailbox the user configures and creates first. The scan for a
      purge/empty/expunge-shaped name covers the three blocks it prints —
      top level, the shared `mailbox` API, the maildir-specific API — and
      finds none in any of them, with its own positive control firing. It
      is **not** a statement about the whole surface: the IMAP-specific API
      does carry an `expunge`, which is an IMAP command and not a route for
      a maildir account, and the transcript names it so the scan cannot be
      read as wider than it is.
    - **The help audit is narrowed to what is checkable.** Modelling
      clap's derive expansion from a regex would agree with the help
      output while both missed a cfg-gated construction, and an extractor
      that finds nothing agrees with everything. What was checked instead:
      the pinned source — digest verified against `freeze-build.txt` —
      declares **no** `hide`, `hide_long_help` or `external_subcommand`
      across 314 `.rs` files, with the same expression shown matching a
      planted attribute. R1's enumeration is not undercut by a command the
      help is told to omit. Whether clap's help is faithful in every other
      respect is still not measured, and would need introspection of the
      compiled command tree.
- **The stock reproduction is done, and it turned the toml's argument
  into a measurement** (`stock-reproduction.txt`). No shim, no engine, no
  seccomp, no `/etc/ld.so.preload`, no interposer: the stock binary under
  strace with one injected signal. Stock copies with a single
  `copy_file_range` of the whole 307-byte message, not the read/write
  loop the define measured, and the window is there anyway: the kill
  leaves a 0-byte message at its final path in the target folder,
  himalaya lists it as an ordinary envelope, and `message read` on it
  fails. The apparatus decided what the engine could see. It did not make
  the finding.
- **Novelty was cleared at selection time**, not here
  (`../novelty-prescan-himalaya.txt`, rule 14): 51 terms, controls green,
  nothing on the tracker describing this write shape. That is evidence a
  known shape was looked for and not found, which is all a clean scan can
  be.

## The apparatus, and what it does not buy

`no-accel-copy.so` answers `copy_file_range`, `sendfile` and
`sendfile64` in userspace so the syscall is never made. It exists
because r1 refused: the seccomp profile made those calls *fail*, and the
oracle refuses on a call being *observed*. The apparatus decides what the
engine can see. It does not create the kill window, and it does not
touch the checker, the property, the fixtures or the argv, all of which
are r1's byte for byte.
