# Results — 2026-10-02 gate-cleared-twelve

The released v1.7.0, in the 2026-09-28 box, on the twelve tools that cleared that run's entry
gate and were not explored, and on rumdl with the step its refusal named. **Twelve FAILs and one
PASS.** Eleven of the FAILs are one shape — the file being rewritten is cut to zero bytes before
the new bytes are written, and the old bytes are nowhere; the twelfth, gofumpt, leaves a file
that is neither old nor new with the original whole in a backup beside it. Every FAIL was
replayed twice by `run.sh` and reproduced both times — except tombi's, where 17 of 20 replays
reproduced and 3 refused (below). Every PASS and FAIL is `oracle_verified`. No define carries a
checker, so each verdict is the built-in rule's (`SELECTION.md`).

Two of the twelve were reported upstream, helm and tombi (below). Two upstream fixes were
measured in the same sitting, each beside its parent commit: both close the window this project
reported, and of what was asked of them — three modes, one relative symlink run from its parent
directory, a second hard link — the hard link is the one thing the old write kept that they do
not.

## The twelve

`transcripts/<target>/`; sizes are the evidence bundle's (`*.evidence.md`, and the case beside
it): the rewritten file before the operation, after it completed, and in the failing world.

| Target | Mode it was judged in | Verdict | Earliest failing crash point | Before → completed, and in the failing world | The same without a kill (`ulimit -f 0`, `transcripts/ulimit.txt`) |
|---|---|---|---|---|---|
| alejandra 4.0.0 | supervised | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 58 → 59; **0** | 0 bytes, killed by the limit's signal (exit 153) |
| biome 2.5.14 | default | FAIL 1 of 4 | 3 of 3, after `truncate`, before `write` | 48 → 59; **0** | 0 bytes, exit 153 |
| gofumpt 0.12.0 | supervised | FAIL 1 of 7 | 5 of 6, after `write`, before `truncate` | 73 → 68; **73, neither** — the original is whole in `main.go.<digits>` | the bytes it had before, the backup left beside it, exit 2 (`write main.go.<digits>: file too large`) |
| helm 4.3.0 `repo remove` | supervised | FAIL 1 of 5 | 2 of 4, after `open`, before `write` of `repositories.yaml` | 163 → 249; **0** | 0 bytes, exit 1 (`Error: write … repositories.yaml: file too large`) |
| jsonnetfmt 0.22.0 | supervised | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 41 → 45; **0** | 0 bytes, exit 1 |
| ktfmt 0.64 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 55 → 70; **0** | 0 bytes, exit 1 (`File too large; skipping.`) |
| oxfmt 0.70.0 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 48 → 60; **0** | 0 bytes, exit 2 |
| pg_format 5.6 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 29 → 49; **0** | 0 bytes, exit 153 |
| pint 1.32.1 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 39 → 45; **0** | **not reproduced this way**: the bytes it had before, exit 153 — PHP dies writing the phar's own temporary file under the system temporary directory, and `a.php` is never opened for writing (`transcripts/pint-ulimit.txt`) |
| scalafmt 3.11.5 | default | FAIL 1 of 4 | 3 of 3, after `truncate`, before `write` | 55 → 61; **0** | 0 bytes, exit 153 |
| tombi 1.5.6 | supervised | FAIL 1 of 4 in 35 of 36 explores and in 17 of 20 replays; UNKNOWN `multiple_threads_detected` in the other 1 and 3 (below; `transcripts/tombi-repeat/all-runs.txt`) | 3 of 3, after `truncate`, before `write`, in all 35 | 36 → 37; **0** | 0 bytes, exit 153 |
| yamlfmt 0.21.0 | supervised | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 46 → 36; **0** | 0 bytes, exit 1 |

The failing world is one crash point in each: the kill lands in the single gap between cutting
the file and writing it. helm's is the one that is not a source file — `repositories.yaml` is the
user's list of chart repositories, and the kubectl row of 2026-09-28 is its shape.

tombi's row stands on more than one run. Its first run through `run.sh` is the refusal
(`transcripts/tombi-r1/`); the replays for 1.5.6 are those of the ten later runs through
`run.sh`, two each. The first of the ten is kept whole (`transcripts/tombi-repeat/run-sh-1/`,
both replays FAIL), and so are the replays of the three runs whose second replay refused
(`run-sh-5/`, `run-sh-6/`, `run-sh-8/`).

**The last column was measured twice, and the first measurement was wrong in its exit codes.**
`ulimit.sh` first sent the tool's output to a regular file inside the limited shell, where the
limit applies to the tool's own stdout too: every message came back empty and oxfmt's exit read
134 (`Aborted`) where it is 2 (`transcripts/ulimit-first-attempt.txt`). The first review found
it. The column above is the second measurement — output through a pipe, and the file compared
byte for byte with a copy taken before the run rather than by size. Which files end at 0 bytes
did not change; pint's result did not change either, and which write kills it is now read
rather than left open.

## Revision 1 — the six static images, and the sentence that did not send them anywhere

The first pass ran the defines as 2026-09-28 wrote them, the tool named bare (`alejandra -q
a.nix`). All six static images stopped there: `no_shim_marker`, and a `next` sentence about
`--shim` that names no mode (`transcripts/host.txt`; `transcripts/alejandra/explore.txt` and the
five beside it). `run.sh` follows only a refusal whose detail names `--observe supervised`, and
for a bare name v1.7.0's does not. This is what 2026-09-28's Revision 1 met on three targets, and
what `main` has changed since (ADR 0090, not in a release): a user of the released binary is
still stopped here with nothing pointing at supervised.

The six were then named by path (`apparatus/defines/<name>-r1/`, the operation's first word made
`/opt/bin/<name>`, nothing else changed; committed before they ran) and `run.sh` followed the
detail to supervised, as on 2026-09-28. The prediction had written "static, supervised" beside
each of the six without saying the bare name would not get there — the same step, missed a
second time.

## tombi: four refusals in fifty-six supervised runs

tombi's first supervised explore refused: `multiple_threads_detected`, two thread ids of the one
process having written the judged directory in an explored world, `open` on one and `truncate`
on the other (`transcripts/tombi-r1/supervised.txt`). The 2026-09-28 gate had accepted tombi
under supervised, so it was put through that gate again and then repeated
(`apparatus/tombi-repeat.sh`, `transcripts/tombi-repeat/`, `transcripts/entry/rows.txt`). Every
count below is read back from the engine's own output files, one line per run, by
`apparatus/tombi-tally.py` into `transcripts/tombi-repeat/all-runs.txt`:

- the gate's `preflight --twice` under supervised: `recording accepted`, 3 operations, in 26 of
  26 (once through `entry.sh`, then 5, then 20);
- the explore under supervised: FAIL 1 of 4 at crash point 3 of 3 in 35 of 36 — 25 of 25 run
  directly, 10 of 11 through `run.sh`, the one refusal being the first run of all;
- the replays of the ten FAILs found through `run.sh`, two each: FAIL in 17 of 20, and
  `multiple_threads_detected` in 3 — the second replay of the fifth, sixth and eighth runs, each
  naming two thread ids, an `open` and a `truncate` or a `truncate` and a `write`
  (`transcripts/tombi-repeat/run-sh-5/`, `-6/`, `-8/`).

So of 56 explores and replays under supervised, 52 judged and 4 refused; the 26 preflights never
refused. The first write-up of this section said the twenty replays all FAILed. They had been
tallied and the tally was not read to its end; the second review read it.

Two of those passes have no script of their own in `apparatus/`. The pass of five was
`tombi-repeat.sh` as first written, with `1 2 3 4 5` where it now says `$(seq 1 20)`; its
output is `five.txt`. The ten through `run.sh` were a loop typed on the host, `host.sh <a fresh
out directory> tombi-r1` ten times; `through-run-sh.txt` is each run's `summary.txt` followed by
its replay lines.

The refusal is the engine's rule as written: under supervised nothing orders two writing
threads, so it refuses. What was measured is one target: tombi was judged on 52 of 56 runs and
refused on 4, and nothing in a single run says which kind of run it was — a FAIL found on one
run did not reproduce on a replay three times in twenty, not because the window closed but
because the engine could not order the writers that time. Whether other tools that write from a
runtime's thread pool do the same was not measured. Not filed against Sideeye: a refusal is not
a wrong verdict.

`../README.md`'s sunset for the ordering rule asks whether the screen ever says measurable and
the engine then refuses in a phase the preflight ran. This is that case — once in thirty-six
explores and three times in twenty replays — by a rule the preflight does ask and did not trip
in twenty-six tries. One target is not grounds to delete the rule; the counts are here for the
next reader who meets a second.

## rumdl

The 2026-09-28 gate refused rumdl on its own cache under the state directory and named the step:
pin or relocate what differs. `rumdl fmt --no-cache` is that step
(`apparatus/defines/rumdl-nocache/`). Through the same gate: the original define refused again,
the same row; with the flag, accepted, 3 operations (`transcripts/entry/rows.txt`). The explore:
**PASS 4/4** (3 crash points and the baseline), `oracle_verified`
(`transcripts/rumdl-nocache/explore.txt`). rumdl writes a temporary file beside the target and
renames it: under `ulimit -f 0` the file keeps the bytes it had (62, compared with a copy) and
a `.a.md.rumdl-tmp.<pid>.0` is left (`transcripts/ulimit.txt`).

## Against the prediction

`PREDICTION.md`, committed as `141b7a3` at 04:57:51Z; the first explore started at 04:58:01Z
(`transcripts/first-explore-started.txt`).

- **The twelve: twelve FAILs predicted, twelve FAILs.** gofumpt was predicted to keep the
  original elsewhere and does. The three-operation targets (biome, tombi, scalafmt) were read as
  open, cut, write and are; helm was read as `repositories.yaml` rewritten in place and is.
- **rumdl: predicted FAIL, is PASS.** The gate half held (accepted with `--no-cache`).
- **Not predicted:** that the six static images would stop on the bare name, and that tombi
  would be refused at all — once in 36 explores and three times in 20 replays.

Twelve of thirteen verdicts is a weak result about the predictor: 2026-09-28 had already shown
six of six in this shape, and the operation count at the gate is nearly the answer.

## The two upstream fixes

`PREDICTION-fixes.md`, committed as `6fa2d19` before either ran; `apparatus/fix/`;
`transcripts/fix/`. Each tree is run from source in the same box, the fix and its parent commit
on the 2026-09-16 define with that run's checker; `transcripts/fix/host.txt` prints the commit
each run had on `/src`. Neither is a release.

| | codespell `68804d2f` (codespell-project/codespell#4028) | RuboCop `b39e7f467` (rubocop/rubocop#15721) |
|---|---|---|
| the parent, 2026-09-16 define | FAIL 3 of 7, crash point 2 of 6, replayed twice — the 2026-09-16 numbers | FAIL 2 of 5, crash point 2 of 4, replayed twice — the 2026-09-16 numbers |
| the fix, same define | **PASS 10/10** | **PASS 9/9** |
| modes `0600` / `0664` / `0755` | kept | kept |
| relative symlink, run from the parent | link kept, target fixed | link kept, target fixed |
| a second hard link | **detached**: the other name keeps the original bytes (the parent rewrote both names, one inode) | **detached**, as its commit message says; the other name keeps the original bytes |
| `ulimit -f 0` | the original bytes kept, nothing left behind, exit 1 (the parent: 0 bytes) | the original bytes kept, exit 153 — and a `*.rubocop.tmp` **left behind** (the parent: 0 bytes) |
| SIGKILL on entry to the rename | the original bytes kept, a `.codespell-*.tmp` left | the original bytes kept, a `*.rubocop.tmp` left |

"The original bytes" is a comparison with a copy taken before the run. The first version of
these probes read sizes only, and codespell's correction is the same length as the misspelling —
43 bytes before and after — so a size could not tell the two apart; the first review found it,
and the table is the re-measurement.

Against the prediction: thirteen of fourteen cells. The miss is RuboCop under `ulimit -f 0`:
predicted to leave nothing because an `ensure` removes the temporary file, it leaves one, because
Ruby dies on the signal (exit 153) and the `ensure` never runs. The original is intact either
way.

Both fixes close the reported window. Two things are different from the write they replace: a
second hard link is detached — RuboCop's commit names that, codespell's does not — and a killed
or signalled run leaves a temporary file beside the original, where the old write left an empty
file and nothing else. Neither loses bytes the old write kept, in what was asked: three modes,
one relative symlink run from the parent directory, one extra hard link, as root. Owner and
group, an absolute symlink, a symlink run from another directory, and a directory that refuses
new files were not asked — and the terraform fix of 2026-09-29 turned on exactly which directory
a link was resolved from. The two fixes of this shape measured before (ImageMagick 2026-09-06,
terraform 2026-09-29) each lost something the old write kept; in what was measured, these two
do not.

One reading that is not the fix's: the parent RuboCop, which renames nothing for the source file,
also exits 137 under the rename probe — its result cache is saved by a rename, after the source
file was written (`transcripts/fix/rubocop-base.txt`: the file is already rewritten). In the
fix's transcript the file still holds its original bytes and the temporary holds the corrected
19, so the rename killed there is the source file's.

These four runs were made three times. The first reached no explore: `measure.sh` removed the
state directory's parent and the engine makes only the leaf — four `SETUP_ERROR`s, kept with
their probe output in `transcripts/fix/first-attempt-setup-error/`. One line was added and all
four re-run; that second pass is the one with size-only probes, and it is in this branch's
history (`ff7a7e5`) rather than the tree. The third, with the comparison, is what
`transcripts/fix/` holds.

## Novelty and reporting

The novelty check came after the explores, not before them (`SELECTION.md`). For each of the
twelve FAILs it read the writer on the default branch, the releases since the measured one, the
tracker, and the project's rules for reports (`transcripts/receipts/after-the-fail.txt`; every
writer line and every quoted policy line there was re-read by hand at the commit it names, and
the search counts are the reading agents').

**All twelve write the same way on their default branch today, and no tracker holds a report of
this shape.** Two were filed — the owner's ruling, 2026-10-02, on those receipts — and each text
was shown to the owner in full and posted unchanged:

- **helm: filed as helm/helm#32709** (`report-helm.md`). The one target here that is not a source
  file: `repositories.yaml` is a user's list of chart repositories, with their credentials. The
  2026-09-28 kubectl finding is the same window on the same kind of file and was not filed — one
  write long, and a kubeconfig can usually be regenerated. What helm has that kubectl did not is
  its own record: the write was made atomic in 2017 (helm/helm#2449), reverted for a dependency's
  licence with a note that it would need re-implementing (helm/helm#2938), and re-implemented in
  2020 for `index.yaml` only (helm/helm#7954). Today `index.go` and `chartrepo.go` in the same
  package write through `fileutil.AtomicWriteFile` and `repo.go` line 124 is `os.WriteFile`.
  v4.3.0, the measured release, is the latest. No policy on AI use was found; the report carries
  a disclosure.
- **tombi: filed as tombi-toml/tombi#2265** (`report-tombi.md`), in its form's fields. A
  formatter rewriting a working tree, the reason ast-grep, nbQA and terraform were filed on. The
  box holds 1.5.6 and v1.7.0 came out the day before, so the release binary was measured first:
  FAIL 1 of 4 in the same place, replayed twice, and 0 bytes under `ulimit -f 0`
  (`PREDICTION-latest.md`, `transcripts/latest/`). Its maintainer answered ten of the last ten
  outside reports. No policy on AI use was found; the report carries a disclosure.

What each report quotes was run as the report's own steps
(`apparatus/report-evidence.sh`, `transcripts/report-evidence-helm.txt` and `-tombi.txt`). The
first review read both reports against the upstream source and those transcripts and found
nothing false. One line in tombi's is loose and stays as posted: "opened read-write (line 550)"
— line 550 is where the open options are built, and the `open` itself is at line 558.

Whether each target has released since the version measured
(`transcripts/receipts/after-the-fail.txt`): tombi and biome have, and their latest releases
were measured (`transcripts/latest/`; `assets.txt` there holds each asset's sha256 against the digest GitHub
publishes, and the sha256 of the tombi binary unpacked from its tarball, which is the one
`host.txt` printed for the binary that ran). oxfmt (0.71.0), pg_format (5.7 to 5.11) and the PHP-CS-Fixer inside pint (two
releases past the bundled one) have too, and **were not measured**: for those three, "the same
writer on the default branch" is a reading of source. For the other seven the measured version
is the latest release.

The other ten FAILs are not filed:

| Target | Why not |
|---|---|
| biome | Its `CONTRIBUTING.md` asks that contributor communication not be written with AI, so the text would have to be the owner's own; not taken up. Measured again on 2.5.15, the latest: the same FAIL (`transcripts/latest/`). Its tracker holds the opposite observation — a reporter who looked for truncation on a 40-file `--write` run and found none (biomejs/biome#11817) |
| oxfmt | The same project answered the same shape for its linter in 2024 (oxc-project/oxc#6061): syncing was measured as too slow, the write stayed `fs::write`, and the fix was to write fewer files |
| pg_format | Measured on Debian's 5.6; upstream is at v5.11 with the same `open`, not measured. An earlier report of the file emptied by an exception was fixed on the encoding side only |
| scalafmt | One bug form, shaped for wrong formatting output, blank issues off; seven of the last ten bug reports closed without a comment |
| alejandra | Half of recent bug reports answered, after 6 to 75 days |
| jsonnetfmt | No maintainer reply on the last ten bug reports; no commit since the measured release |
| yamlfmt | One maintainer in spare time; no reply on the six issues opened since February |
| ktfmt | Moved to another organisation; no maintainer reply on recent outside issues |
| pint | Issues are off, and the write is PHP-CS-Fixer's, whose form requires a reproduction on its own latest release — not measured here. A batch of file-handling reports reached that project privately in September and its content is not visible |
| gofumpt | The write is Go's own `gofmt`, inherited: a backup, an in-place write, a truncate. The original survives in the backup; a pull request to Go to swap the file atomically (golang/go#44173) was closed unmerged, why was not read |

No one of these is a judgement that the finding is not real; each is measured the same way as
the two that were filed.

## Found in passing

- **A gate script of this run's asked the wrong question.** `gate-rumdl.sh` passed `--config`
  to `preflight`, which takes flags only: `SETUP ERROR`, exit 3, twice
  (`transcripts/entry/first-attempt-wrong-flags.txt`). It was replaced by the 2026-09-28
  `entry.sh` and `toml2flags.py`, copied unchanged, which is what should have been used first.
- **pint under `ulimit -f 0` dies before the file is touched** (exit 153, the file's bytes as
  they were): PHP writes the phar's own temporary file first and the limit kills it there, with
  no open of `a.php` for writing in the whole run (`apparatus/pint-ulimit.sh`,
  `transcripts/pint-ulimit.txt`). The explore's FAIL stands on the kill; a limit on file size is
  not a route to it for a phar.
- **Three of this run's own scripts measured less than they said, and the first review caught
  all three.** `ulimit.sh` limited the tool's stdout along with its target (above, under the
  twelve). The fix probes compared sizes where the bytes were the question (above, under the two
  fixes). And `report-evidence.sh` passed strace `-P <absolute path>`, which does not match an
  `openat` given a relative name, so the open was missing from what it printed; nothing in
  either report quotes those lines, and the re-run picks lines by the file's name and shows the
  truncating `openat` for helm and the read-write `openat`, `ftruncate` and `write` for tombi
  (the `write`'s return value is on a line without the name, which that filter drops).
- **The redirect that was wrong in `ulimit.sh` is in two earlier runs' probes, and their records
  do not lean on what it distorts.** `2026-09-16-outside-git/apparatus/probe-ulimit.sh` (aws-cli,
  neovim, jbang, pyenv), `probe-shada-large.sh` there, and the Bun leg of
  `2026-09-16-crossed-walls/apparatus/probe-ulimit.sh` send the tool's output to a regular file
  inside the limited shell. It shows: aws-cli's exit reads 120 in that probe's transcript and 255
  in `report-repro.txt`, which leaves stdout alone and is what the upstream report quotes. Those
  runs' `RESULTS.md` files quote the size the target file was left at, which the redirect does
  not touch, and not the exit codes (searched for the 120). Read, not re-measured: the 2026-09-16
  boxes are gone. Not filed.
- **The refusal and the `processes` line of the same report read as if they disagree.** tombi's
  refusal names two thread ids that wrote in an explored world; the `processes` line under it
  says one thread id of the subject wrote the judged directory
  (`transcripts/tombi-r1/supervised.txt`). The second is probably the recording run's count and
  the first an explored world's — a reading, not checked against the engine's source. Not filed.
