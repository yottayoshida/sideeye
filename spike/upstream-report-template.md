# Filing a finding upstream — the shape

Eleven reports have gone out from this project (`upstream-reports.tsv`; ten
standing, one withdrawn). **Four** of them, filed 2026-09-04..05, share one
skeleton, and `ImageMagick/ImageMagick#8939` is the canonical instance — the
owner's instruction on 2026-09-06 is that later reports go the same way. This
page is that skeleton written out, so the next report is not re-derived from the
last four.

The worked examples are the real instrument; this page is an index to them.

| Report | What the crash leaves | Text |
|---|---|---|
| `ImageMagick/ImageMagick#8939` | the original at `<file>~` | `dogfood/2026-09-05-userview/report-imagemagick.md` |
| `qpdf/qpdf#1773` | the original at `<file>.~qpdf-orig#` | on the tracker only |
| `andreafrancia/trash-cli#414` | the user's file untouched, the trash directory permanently inconsistent | on the tracker only |
| `Exiv2/exiv2#9482` | a zero-byte file, the original bytes nowhere | `dogfood/2026-09-05-userview/report-exiv2.md` |

## The opening paragraph: what was lost decides it, not how bad it feels

Three openings, and the measurement picks one. **Write the recovery down first.**
If it is one command, the finding is the first kind; if it takes a human deciding
which file to delete, it is the second; if there is no recovery, it is the third.

| The recovery | The opening | The fourth section |
|---|---|---|
| one command (`mv img1.png~ img1.png`, `mv f.pdf.~qpdf-orig# f.pdf`) | `**Up front: this is minor, and closing it as won't-fix is a perfectly good outcome.**` | *Why it might still be worth a line of documentation* |
| a human must work out what to delete, and the tool complains on every run until they do | `**No data is lost by this.**` — then, in the same paragraph, what *does* break and that it stays broken | *What would close it* |
| none — the bytes are gone | no mitigating opening at all | *Why this one may be worth more than the usual in-place-write report* |

The middle row is trash-cli#414 and it is why this is a three-way branch rather
than the two-way one this page shipped with: no data is lost there, and calling
it minor would still have been wrong, because every later `trash-list` prints a
parse error and only a hand-deleted file stops it. The bottom row must not carry
a mitigating opening at all — calling unrecoverable loss minor is a false
statement, not a courtesy.

## Before any text is written

1. **Freshness against more than this repository.** `git grep` here returned
   nothing for qpdf and the finding was written up as fresh; the owner had filed
   `qpdf#1773` the previous day from a separate measurement, and the tool is in
   production in four of the owner's work repositories. Search the target's own
   tracker (`cohort4/novelty-prescan.sh`, one word per query — multi-word queries
   silently return zero), this repository, and the owner's own filings.
2. **Read the current upstream source, not only the packaged build, and say in
   the report that you did.** All four were measured on a packaged build —
   Debian for three, pip for trash-cli — and three of the four carry the
   sentence (`The current main carries the same block`); qpdf#1773 does not,
   which is the gap to close rather than the precedent to follow. A report
   measured only on a packaged build is invalid the moment upstream has already
   fixed it.
3. **Owner sign-off on the full text, verbatim** — not a summary, and with no
   Japanese around it. A draft shown with Japanese commentary was read as though
   the commentary were part of the report.

## The sections, in order

### The opening paragraph

Per the table above. One paragraph, bold lead, before any heading.

### `## What happens`

The mechanism, with the target's own source quoted and the file named —
`MagickWand/mogrify.c`, `FileIo::transfer` in `src/basicio.cpp`, `writeOutfile`
in `QPDFJob.cc`, `Janitor.trash_file_in` in `trashcli/put/janitor.py`. Separate
what the design already handles from what it cannot: mogrify's report says the
code renames the backup back when a write fails, and that a killed process
reaches neither branch. That sentence is what keeps the report from reading as
"you forgot your error handling".

### `## Measured`

Six things, each a literal rather than a characterisation:

- version, package name, distribution, architecture;
- the write path as `strace` printed it — the real lines — or, where the damage
  is what the tool says afterwards, that output verbatim (`trash-list`'s parse
  error, and that it still exits 0);
- which crash point of how many (`crash point 5 of 6`);
- the directory before and after, with byte counts;
- the recovery **run**, not asserted (`identify img1.png~` succeeds and reports
  the original dimensions) — or what a user has to do by hand, or that the bytes
  are nowhere;
- how many explored worlds showed it, that the invariant is named, and that a
  second witness agreed.

### `## Why this is different from #NNN` — only when the tracker holds a near neighbour

The novelty check happens before the report is written; this section is where
its result is shown to the reader instead of kept. trash-cli#414 carries it
because `#322` looks like the same bug and is not: that one was a multi-file
`trash-put`, fixed in 2024, and this window is inside `trash_file_in` on a
single file. Name the neighbour, name the mechanism difference, say the current
code is unchanged.

### The fourth section — why it is worth anything at all

Recoverable: discoverability is the argument, never severity. #8939 and #1773
make it the same way — the backup is the right thing to have kept, but only for
someone who knows to look, and the documentation does not mention it.

State-broken: `## What would close it`, because there is no version of "leave it"
that is not an error printed forever.

Unrecoverable: the argument is what the data is, and it needs the cheaper
same-shape finding beside it to carry — black rewrites files that sit under
version control; photographs do not.

In all three, the responses are **at most two, in increasing order of cost, with
`I have no stake in which`**, and the more expensive one carries the sentence
that it may well not be worth it. All four reports do this; it is not the fix
section that was struck (see below).

### `## Disclosure`

Four elements, of which (c) and (d) are what stop it reading as promotion:
(a) the tool named and linked; (b) one or two sentences on what it does;
(c) no commercial interest, a personal open-source project; (d) *if you would
rather not have tool-generated reports on this tracker, say so and I will stop*.

Then the invariant in one sentence, and — where it was run — that the checker
was falsified against deliberately corrupted state before the run, so a checker
that could not fail did not produce this.

### `## Not claimed`

Name what was not measured: power loss, torn writes, concurrent processes.
Process-kill granularity says what happens when the process dies between two
syscalls and nothing about what the filesystem does with partially-flushed data.
Then the target-specific gap — which argument was incidental (`-resize` is not
the subject; any in-place `mogrify` reaches the same rename), or which variant
was not measured (trash-cli's multi-path forms).

## What does not go in

- **A tested patch, or an offer to send a PR.** What was struck from the
  timewarrior draft was a section headed *A fix direction, tested* and the line
  *Happy to turn this into a PR if the direction looks right to you* — the
  patch and the offer, not the direction. Naming one or two directions is what
  all four reports do. A verified patch stays local until the maintainer engages.
- **An opening that is not a fact** — thanks, or an aside addressed to whoever
  reads this later. Start with the finding.
- **The reporter's future plans.** `I am not planning to take this further` is
  information nobody asked for, and closing the issue already says it.
- Em dashes are fine. The 2026-08-23 ban was lifted on 2026-09-05 by
  measurement: the owner's own `qpdf#1773` carries eight of them and names
  sideeye four times.

## After filing

- **Both records, in the same sitting**: a row in `upstream-reports.tsv` and an
  `<!-- upstream-report: owner/repo#N -->` marker on that tool's row in
  `docs/target-classes.md`. `check-upstream-ledger.sh` holds the two to each
  other and stays green over a filing that is in neither — that is the gap
  `trash-cli#414` sat in for two days.
- **Closing your own report uses `not planned`**, never `gh issue close`'s
  default `completed`.
- **A third party's question on your issue gets an answer**, even when the
  answer is that you are not the one who decides.

## What this page cannot tell you

Whether the shape works. Ten standing reports, measured 2026-09-06 with
`upstream-report-status.sh`: seven at zero comments, three with any reply at all.
#8939 is the only Up-front-shaped one, and it drew a maintainer reproduction and
a patch commitment within fourteen hours — on a report that told them closing it
was fine. That is n=1 against a variable this page does not control: rule 11 in
`cohort4/SCOUT-BRIEF.md` exists because projects differ in responsiveness, and
nothing here separates the shape from the project.

## Sunset

Delete this page if the next three reports each need a section it does not have,
or need one of its sections dropped. It has already been wrong once in that
direction: the first version read three reports, called the branch two-way, and
banned the fix direction that all four reports carry — trash-cli#414, which was
on the ledger the whole time, falsified both. Four worked examples are a better
instrument than a bad abstraction of them.

Delete element (d) of Disclosure — not the page — if a maintainer ever takes it
up. Nobody has.
