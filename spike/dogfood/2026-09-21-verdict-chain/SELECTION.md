# Selection — 2026-09-21 verdict-chain

The follow-up to [2026-09-21-release-path](../2026-09-21-release-path/), which spent its
only target slot on a statically linked binary and stopped at `attempted`. That run did
measure linkage before writing its candidate table, as `spike/dogfood/README.md` requires;
what it did not do was read the probe's output past `ELF 64-bit LSB executable`, with
`statically linked` further along the same line.

**So the entry gate here answers with an exit code instead of a line of text**
(`apparatus/gate.sh`), and the gate is shown turning away that same binary before anything
else is claimed.

## The exclusion set, declared before the candidates

A candidate is *fresh* when it appears in none of the nine ledgers `apparatus/fresh.sh`
searches. Six are the previous campaign's; three are added here:

| ledger | why it is searched |
|---|---|
| `spike/outcome-funnel.tsv` | every target this project has encountered |
| `docs/target-classes.md` | every verdict and every wall |
| `spike/unknown-rate/b-exclusions.txt` | the B-group name exclusions |
| `spike/blind-hunt3/candidates.md` | the blind-hunt 3 taint list |
| `spike/authoring-cost/selection.tsv` + `pool-*.txt` | #618's selection and its four pools |
| `spike/dogfood/*/SELECTION.md` | the candidates earlier runs turned away |
| **`spike/unknown-rate/b2-exclusions.txt`** | **new** — 229 lines, the largest name ledger here, and **the file the previous campaign wrote its own target into as a follow-through**. A checker that does not read what its own campaign writes is a pair that can only drift |
| **`spike/unknown-rate/b2-targets.txt`** | **new** — the 30 names #619 is measuring right now |
| **`spike/unknown-rate/b2-candidates.txt`** | **new** — the 289 names those 30 were drawn from |

The last two are #618's argument applied to #619: a collision reaches a study in flight.
A candidate found in `b2-targets.txt` is dropped at selection rather than patched
afterwards — `spike/unknown-rate/count.py:1736` re-derives that list as the keyed first N
of the candidates minus the exclusions, so excluding one of the 30 promotes the 31st and
turns `spike/acceptance.sh` red. The CI failure is the small half of that; the contaminated
study is the large one.

**What the three new ledgers actually changed, measured rather than asserted**: of 77 names
screened, exactly **one** (`delta`) was caught by them and by nothing else. `b2-exclusions`
matched 29 names, but every one of those was already in another ledger. The hole was real —
it is closed here — and its measured cost so far is one candidate.
(`transcripts/freshness-screen.txt`; the counts are re-derivable from that file.)

## The screen

**77 distinct names screened for freshness, 35 fresh, 42 already met. The 35 are the
campaign's candidate count** — every one of them carries a rule's disposition below, and it
is that number, not the freshness grep's 77, that `spike/outcome-funnel-campaigns.tsv`
records. Two batches: the first is the previous
run's pool minus what it consumed, the second is chosen for the shape this campaign wants —
an in-place mutation whose write path is *not* the truncate-then-write formatter shape that
`docs/target-classes.md` already publishes for black, rustfmt and pyupgrade, since a
rediscovery of that shape reaches `judged` and stops there.

Three names deserve their hit being read rather than counted, because a loose substring
match is what `fresh.sh` uses on purpose: `pre-commit` matches the hook filename in this
project's own lefthook rows — **and is a real meet anyway**, `b2-exclusions:166`
(`pre-commit  measured (outcome-funnel.tsv)`). `rsync` is `funnel:52`, PASS 7/7 in the
2026-09-11 run. `jpegoptim` is in `b2-exclusions` and two earlier SELECTION.md files.
**No false `fresh` and no false `SEEN` in this pool.**

## The candidates

Measured values with the command that produced them. Rule numbers are
`spike/cohort4/SCOUT-BRIEF.md`'s.

### Gated (`apparatus/gate-candidates.sh`, output in `transcripts/gate-candidates.txt`)

| target | visibility | interior | threads | result |
|---|---|---|---|---|
| **overcommit 0.73.0** (Ruby) | **0** | **0** — 3 kill points (a floor; see below) | **0** — 1 writing thread id, 2 clones created | **enters** |
| lefthook 1.13.6 (Go) | **1** | 0 — 4 kill points | 0 — 1 writing thread id, 5 clones | turned away |
| detox (C, Debian) | **0** | **0** — 2 kill points | **0** | clears the gate; excluded on rule 1 |

**These are the second measurement.** The first ran the three gates back to back with no
reset, so `interior` and `threads` saw the operation applied to what the gate before them
had left — for an installer that is a different operation. It put `1 — 0 kill points` and
`visibility 2` against detox, which this page then explained as a property of `detox -r`.
It was a property of the harness. `gate.sh all` now runs a reset before each gate, says so
in its output and stops the row at 2 if the reset fails, and every row above is from a run
that did. The resets themselves are committed — overcommit's is `seed-state.sh`, the define's
own setup, and the other two are written by `gate-candidates.sh`; an earlier version set
`GATE_RESET` to scripts under `/tmp` that this repository does not hold, which left the one
step whose point is that a reader can check it as the one step they could not.

Two of those rows are worth reading rather than skimming.

**lefthook is red on one gate and green on the other two.** That is a stronger statement
than three reds would be: the wall is attributable. It is also the gate set answering the
question the previous campaign got wrong, on the same binary, at the same version — pinned
to 1.13.6 in `apparatus/Dockerfile` for exactly that reason, since upstream is at 2.1.14
and any other build would be a different measurement.

**detox clears all three gates and still does not enter.** It is a real, dynamically
linked C tool that mutates files in place, and rule 1 is the only thing that stops it: no
GitHub home with 1,000 stars. The row is here because a gate whose greens are all toys has
only been shown half its range, and this is the half that is a real binary.

**The interior counts are floors, and for overcommit the floor is ten times under.**
`preflight.sh`'s trace set is `%file,write,pwrite64,writev,fsync,fdatasync,ftruncate`.
`overcommit --install` moves its bytes with **`copy_file_range`**, ten times — measured in
`transcripts/copy-file-range-and-third-sweep.txt`: twenty `openat`s, ten `copy_file_range`s,
one `mkdirat` and one `unlinkat` naming a path under the hooks directory, with three of the
ten copies quoted in full. `copy_file_range` takes descriptors, so it is in neither `%file` nor the
write list, and the gate saw `3 (mkdir=1, open=1, rmdir=1)` where the engine's own run
counted **31 crash points**. Rule 15 asks only for more than one, which both numbers
answer, but the gate's number is not the engine's and this page does not pretend it is.

That syscall is also worth naming for a second reason: #217's body lists raw
`copy_file_range` among the operations `--observe syscalls` cannot trap. This run reached a
verdict because Ruby's call goes through glibc's wrapper, where the shim interposes it. A
target issuing the same call raw would be refused.

### Rejected before the gate

| target(s) | rule | why |
|---|---|---|
| `husky` | **2** | **Measured, not assumed**: latest release v9.1.7 (2024-11-18), last push 2026-03-19 — over six months (`transcripts/stars.txt`). It was the strongest fit on every other rule: 35,328 stars, git hooks, the same operation family as this run's target |
| `zellij`, `helix` | 4, 8 | Interactive; no non-interactive mutating command |
| `watchexec`, `gitleaks`, `difftastic`, `starship` | 5 | No primary data of their own — they watch, scan, diff or print |
| `tealdeer`, `sccache` | 5 | A cache is the one thing users *do* expect to lose |
| `hugo`, `zola`, `mdbook`, `typst`, `pelican`, `fava` | 5 | Output derived from sources the tool does not own; losing it costs a rebuild |
| `atuin`, `zk`, `shiori`, `recoll` | 7 | SQLite or Xapian is the main store |
| `recutils`/`recset`, `sponge`/`moreutils`, `mat2`, `detox`, `jhead`, `pass-otp`, `abcde` | 1 | No GitHub home with 1,000 stars. `recutils` is also **MISSING** from Debian trixie (`transcripts/install.txt`) |
| `asdf`, `rye` | 15 | The version-manager class the previous run measured: they write nothing until the language they manage is installed, a prerequisite heavier than the step under test |
| `pnpm`, `yarn` | — | Not a target property: **this run's explore stage has no network** (`--network none`), and their operation needs a package registry. Recorded as a limit of the apparatus, not of the target |
| `pdfcpu`, `kopia` | 16 | **Forecast, not measured**: statically linked Go. Rule 16 admits a forecast wall only with the apparatus that lifts it named before the probe, and there is none — so the candidates do not enter and no linkage claim is made about them here |

## The slate

**One target: `overcommit` 0.73.0**, operation `overcommit --install`, judged root
`.git/hooks`.

- **Rule 1**: 4,004 stars (`transcripts/stars.txt`, `gh api`).
- **Rule 2**: v0.73.0 released 2026-09-06; last push 2026-09-06.
- **Rule 4**: CLI is the only interface.
- **Rules 5, 6**: ten plain Ruby files in `.git/hooks`, which git executes on the next
  commit. Measured: ten regular files of 3,682 bytes, one distinct md5 between them.
- **Rule 7**: no database anywhere in the judged root.
- **Rule 8**: `overcommit --install` is non-interactive and exits 0 (measured).
- **Rule 9**: the checker is written against the tool's own output shape
  (`apparatus/verify.sh`), falsified before use — `transcripts/checker-falsification.txt`
  holds **five greens and nine reds**, including the state the engine actually corrupts
  (the samples alone, which the checker's first version accepted) and a regular file
  wearing the scratch directory's name.
- **Rule 10**: measured by the gate above, not forecast.
- **Rule 14**: `transcripts/novelty-overcommit.txt` — controls green (the positive control
  returned both known black issues, the negative returned 0), 51 terms, 36 with hits, none
  saturated. **Nothing on the tracker is about `--install` leaving a partial hook.** The
  nearest neighbours are #7 (install should complain when hooks already exist), #138 and
  #141 (save and restore old hooks on uninstall), and a real data-loss family — #65, #135,
  #295 — which is all about the **stash flow during a commit**, a different operation from
  the one this run explores. If this run's define were the commit flow, rule 14 would veto.
- **Rule 15**: 3 kill points inside the judged root, measured by the gate.
- **Rule 16**: no forecast wall. The one this campaign expected — static linkage — is what
  the gate cleared.
- **Rule 13** (language diversity) is a cohort-slate rule and does not bind a one-target
  dogfood run; recorded so its absence is not mistaken for an oversight.

Owner sign-off: given 2026-09-21, on this table.
