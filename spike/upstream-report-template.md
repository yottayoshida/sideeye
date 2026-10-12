# Filing a finding upstream — the shape

Every report this project files on GitHub goes in `spike/upstream-reports.tsv` (a
report filed elsewhere, a Bugzilla say, has no row there yet), and `docs/found.md`
lists those with their state. This page is the shape a report takes. **It is short.**

## Why short

A maintainer reads the first screen and decides. Long, sectioned reports have been
answered as what they look like, not as what they found:

- `crystal-lang/crystal#17620` (2026-10-12), within the hour: *"Don't paste AI. Especially
  walls of slop. Write down a quo summary of findings in your very own voice."* [sic] — an answer
  to the report's form; the finding, a source file left at 0 bytes, went unaddressed.
- `libjpeg-turbo/libjpeg-turbo#914` was called an "AI-generated novel", `pyupgrade#1101` was
  locked as spam, and `poetry#11019` drew "your AI" (2026-09). The first two carried the old
  shape: six measured items, the full trace, a section on why it mattered, another on what
  was not claimed.
- The two reports filed after that comment (`rclone/rclone#10076`, `FreeCAD/FreeCAD#33493`) were
  shortened at the owner's request before they went out.

Length is not where the evidence lives. The run's `RESULTS.md` and its transcripts hold
every number; the report points at what a maintainer needs to see the bug, and stops.

## Before any text is written

0. **Read the project's contribution policy on LLM-written text.** Where it bans an issue body
   an LLM wrote, or asks that descriptions be the contributor's own (rust-lang's policy,
   adopted by cargo, closed `rust-lang/cargo#17481` within the hour; FreeCAD's `AI_POLICY.md`),
   the owner writes the text in their own words — in Japanese if they like — and the agent may
   translate it, marked as a translation as the policy asks, with the original beside it where the
   policy asks for that; translate, never compose. Where it allows assistance on conditions (aws-cli,
   ansible's community policy: an `Assisted-by:` line), meet them in the text. Record where the
   policy was read, in the draft's header comment.
1. **Read the issue form field by field.** A tracker's `.github/ISSUE_TEMPLATE/*.yml` names its
   required fields (`validations.required: true`); fill every one, briefly, under the form's own
   headings. `ansible/ansible#87678` was closed by the project's bot 42 seconds after filing for
   two required sections the text did not have, and had to be filed again as #87679. A checkbox
   is a statement: tick "I searched the forum" only after searching it.
2. **Freshness against more than this repository.** Search the target's own tracker (one word
   per query — multi-word queries silently return zero), its forum where it has one, this
   repository, and the owner's own filings. `qpdf#1773` was written up as fresh the day after
   the owner had filed it.
3. **Read the current upstream source, and measure the latest release** — the development
   release where the form asks for it (FreeCAD's does). A report measured only on a packaged
   build is void the moment upstream has fixed it.
4. **The owner's own voice, in every report.** The agent hands over the facts — what a kill
   leaves, where in the source, how to reproduce, one way to close it — and the owner writes the
   text. A short draft from the agent is a starting point the owner rewrites in their own words,
   never a text they approve as it stands: `crystal-lang/crystal#17620` was an agent's draft
   approved verbatim. The owner then approves the final text as it will be posted, with no
   Japanese around it.

## The shape

Under the form's headings where there is a form, in this order where there is not. Aim for a
first screen: a few short paragraphs, about 250 words before any required raw output (version
strings, config dumps, logs).

1. **What a kill leaves, in one paragraph.** Write the recovery down first; it picks the opening:

   | The recovery | The opening |
   |---|---|
   | one command (`mv part.<date>.FCBak part.FCStd`) | say it is minor, and that closing it is fine |
   | a human must work out what to rename or delete, and the tool stays broken until they do | *No data is lost by this*, then what breaks and that it stays broken |
   | none — the bytes are gone | no mitigating opening at all; calling unrecoverable loss minor is false |

2. **Where.** One source location (`src/App/Document.cpp`, `fs/config/configfile/configfile.go`)
   and one sentence on what the code already handles and what a killed process does not reach
   — the sentence that keeps it from reading as "you forgot your error handling". Where the tracker
   holds a near neighbour, one more sentence on how this differs (`trash-cli#414` is not `#322`:
   that one was a multi-file `trash-put`, fixed in 2024).
3. **How to reproduce.** The version, the command, and the one or two system calls either side
   of the window (`renameat` … `renameat`, `openat(… O_TRUNC)` … `write`). What was left, in a
   line. No world counts, no invariant names, no full trace.
4. **One way to close it**, and where it is true, that not fixing it is fine.
5. **Disclosure, in one or two sentences**: found with Sideeye (linked), a personal open-source
   project with no commercial interest; the AI assistance, as the project's policy asks it to be
   said.

## What does not go in

- **A tested patch, or an offer to send a PR.** Naming a direction is fine; a verified patch
  stays local until the maintainer engages.
- **Sections the tracker did not ask for**: *Measured*, *Why this may be worth more*, *Not
  claimed*. One clause can carry a limit that matters ("power loss was not measured").
- **Raw output beyond the window**: the trace, the evidence table, the replay log.
- **An opening that is not a fact** — thanks, an aside, the reporter's plans.

## The second contact: when the maintainer acts on it

Measure the patched build before replying. `ImageMagick/ImageMagick#8939` drew a patch within a
day that lost the original image with no crash at all (`dogfood/2026-09-06-imagemagick-refix/`);
the reply that said so could carry what a first report must not — the offer of a PR with the
sentence that keeps it an offer, a fix direction with its open details named, and reverting
named as an acceptable outcome. Keep it as short as the first report.

## After filing

- **Watch the first minutes.** A project's bot can close a report it reads as incomplete. If it
  does, file again with what it named, and record the first filing as `withdrawn`.
- **Every record, in the same sitting**: a row in `spike/upstream-reports.tsv`; an
  `<!-- upstream-report: owner/repo#N -->` marker on that tool's row in
  `docs/target-classes.md` (`spike/check-upstream-ledger.sh` holds the two to each other); a row
  in `spike/unknown-rate/b2-exclusion-aliases.tsv` for the ledger's spelling of the tool
  (`count.py b2-selection`); the campaign's row in `spike/outcome-funnel.tsv` at `filed`; a row
  in `spike/campaign-versions.tsv` for that campaign if it has none; then
  `python3 spike/outcome-funnel.py --write-doc`. CI is red until all of it is done. If it is not
  done, the daily `upstream-watch` job still proposes the report for `docs/found.md`, marked not
  recorded yet — provided the report names Sideeye, as the Disclosure has it do.
- **The text as filed** goes beside the run's results (`report-<tool>.md`), its header comment
  naming the policy read and anything changed between draft and filing.
- **Closing your own report uses `not planned`**, never `gh issue close`'s default `completed`.
- **A third party's question on your issue gets an answer**, even when the answer is that you
  are not the one who decides.

## What this page cannot tell you

Whether a short report is answered more often than a long one. Measured on 2026-09-14, six of
the nine reports carrying the old Disclosure drew a reply, and three reports in all drew remarks
on how they were produced; the old version of this page counted them (`git log` on this file). The
four filed on 2026-10-12 are too new to count. Nothing here separates the shape from the
project.

## Sunset

Rewrite this page when the next three reports each need something it does not say, or the
owner cuts what it does say — which is how the long version ended (2026-10-12). Delete the
250-word aim if a maintainer asks for more detail than it allows, twice.
