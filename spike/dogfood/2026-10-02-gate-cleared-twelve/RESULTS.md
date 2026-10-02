# Results — 2026-10-02 gate-cleared-twelve

The released v1.7.0, in the 2026-09-28 box, on the twelve tools that cleared that run's entry
gate and were not explored, and on rumdl with the step its refusal named. **Twelve FAILs and one
PASS.** Eleven of the FAILs are one shape — the file being rewritten is cut to zero bytes before
the new bytes are written, and the old bytes are nowhere; the twelfth, gofumpt, leaves a file
that is neither old nor new with the original whole in a backup beside it. Every FAIL was
replayed twice by `run.sh`; every verdict is `oracle_verified`. No define carries a checker, so
each verdict is the built-in rule's (`SELECTION.md`).

Two upstream fixes were measured in the same sitting, each beside its parent commit: both close
the window this project reported and neither breaks what the old write kept, except a second
hard link.

## The twelve

`transcripts/<target>/`; sizes are the evidence bundle's (`*.evidence.md`, and the case beside
it): the rewritten file before the operation, after it completed, and in the failing world.

| Target | Mode it was judged in | Verdict | Earliest failing crash point | Before → completed, and in the failing world | The same without a kill (`ulimit -f 0`, `transcripts/ulimit.txt`) |
|---|---|---|---|---|---|
| alejandra 4.0.0 | supervised | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 58 → 59; **0** | 0 bytes, exit 153 |
| biome 2.5.14 | default | FAIL 1 of 4 | 3 of 3, after `truncate`, before `write` | 48 → 59; **0** | 0 bytes, exit 153 |
| gofumpt 0.12.0 | supervised | FAIL 1 of 7 | 5 of 6, after `write`, before `truncate` | 73 → 68; **73, neither** — the original is whole in `main.go.<digits>` | unchanged at 73, the backup left beside it, exit 2 |
| helm 4.3.0 `repo remove` | supervised | FAIL 1 of 5 | 2 of 4, after `open`, before `write` of `repositories.yaml` | 163 → 249; **0** | 0 bytes, exit 1 |
| jsonnetfmt 0.22.0 | supervised | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 41 → 45; **0** | 0 bytes, exit 1 |
| ktfmt 0.64 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 55 → 70; **0** | 0 bytes, exit 1 |
| oxfmt 0.70.0 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 48 → 60; **0** | 0 bytes, exit 134 (`Aborted`) |
| pg_format 5.6 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 29 → 49; **0** | 0 bytes, exit 153 |
| pint 1.32.1 | default | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 39 → 45; **0** | **not reproduced**: unchanged at 39, exit 153 — it died before it reached the file, on which write was not looked at |
| scalafmt 3.11.5 | default | FAIL 1 of 4 | 3 of 3, after `truncate`, before `write` | 55 → 61; **0** | 0 bytes, exit 153 |
| tombi 1.5.6 | supervised | FAIL 1 of 4 in 35 of 36 explores; UNKNOWN `multiple_threads_detected` in 1 (below) | 3 of 3, after `truncate`, before `write` | 36 → 37; **0** | 0 bytes, exit 153 |
| yamlfmt 0.21.0 | supervised | FAIL 1 of 3 | 2 of 2, after `open`, before `write` | 46 → 36; **0** | 0 bytes, exit 1 |

The failing world is one crash point in each: the kill lands in the single gap between cutting
the file and writing it. helm's is the one that is not a source file — `repositories.yaml` is the
user's list of chart repositories, and the kubectl row of 2026-09-28 is its shape.

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

## tombi: one refusal in thirty-six

tombi's first supervised explore refused: `multiple_threads_detected`, two thread ids of the one
process having written the judged directory in an explored world, `open` on one and `truncate`
on the other (`transcripts/tombi-r1/supervised.txt`). The 2026-09-28 gate had accepted tombi
under supervised, so it was put through that gate again and then repeated
(`apparatus/tombi-repeat.sh`, `transcripts/tombi-repeat/`, `transcripts/entry/rows.txt`):

- the gate's `preflight --twice` under supervised: accepted 26 of 26 (once through `entry.sh`,
  then 5, then 20);
- the explore under supervised: FAIL in 35 of 36 — 25 of 25 run directly, 10 of 11 through
  `run.sh`, the one refusal being the first run of all.

The refusal is the engine's rule as written: under supervised nothing orders two writing
threads, so it refuses. It is also rare enough that the gate, whose `--twice` runs the target twice
under supervised, did not meet it in twenty-six tries. A target whose writes can land on two threads of an async runtime's pool is
judged most of the time and refused some of the time, and nothing in a single run says which
kind of run it was. Not filed against Sideeye: a refusal is not a wrong verdict.

`../README.md`'s sunset for the ordering rule asks whether the screen ever says measurable and
the engine then refuses in a phase the preflight ran. This is that case once in thirty-six, by a
rule the preflight does ask; the rule is not deleted on one occurrence, and the count is here
for the next reader who meets a second.

## rumdl

The 2026-09-28 gate refused rumdl on its own cache under the state directory and named the step:
pin or relocate what differs. `rumdl fmt --no-cache` is that step
(`apparatus/defines/rumdl-nocache/`). Through the same gate: the original define refused again,
the same row; with the flag, accepted, 3 operations (`transcripts/entry/rows.txt`). The explore:
**PASS 4/4** (3 crash points and the baseline), `oracle_verified`
(`transcripts/rumdl-nocache/explore.txt`). rumdl writes a temporary file beside the target and
renames it: under `ulimit -f 0` the file keeps its 62 bytes and a `.a.md.rumdl-tmp.<pid>.0` is
left (`transcripts/ulimit.txt`).

## Against the prediction

`PREDICTION.md`, committed as `141b7a3` at 04:57:51Z; the first explore started at 04:58:01Z
(`transcripts/first-explore-started.txt`).

- **The twelve: twelve FAILs predicted, twelve FAILs.** gofumpt was predicted to keep the
  original elsewhere and does. The three-operation targets (biome, tombi, scalafmt) were read as
  open, cut, write and are; helm was read as `repositories.yaml` rewritten in place and is.
- **rumdl: predicted FAIL, is PASS.** The gate half held (accepted with `--no-cache`).
- **Not predicted:** that the six static images would stop on the bare name, and that tombi
  would be refused once.

Twelve of thirteen verdicts is a weak result about the predictor: 2026-09-28 had already shown
six of six in this shape, and the operation count at the gate is nearly the answer.

## The two upstream fixes

`PREDICTION-fixes.md`, committed as `6fa2d19` before either ran; `apparatus/fix/`;
`transcripts/fix/`. Each tree is run from source in the same box, the fix and its parent commit
on the 2026-09-16 define with that run's checker. Neither is a release.

| | codespell `68804d2f` (codespell-project/codespell#4028) | RuboCop `b39e7f467` (rubocop/rubocop#15721) |
|---|---|---|
| the parent, 2026-09-16 define | FAIL 3 of 7, crash point 2 of 6, replayed twice — the 2026-09-16 numbers | FAIL 2 of 5, crash point 2 of 4, replayed twice — the 2026-09-16 numbers |
| the fix, same define | **PASS 10/10** | **PASS 9/9** |
| modes `0600` / `0664` / `0755` | kept | kept |
| relative symlink, run from the parent | link kept, target fixed | link kept, target fixed |
| a second hard link | **detached**: the other name keeps the old bytes (the parent kept both names on one inode) | **detached**, as its commit message says |
| `ulimit -f 0` | the original kept (43 bytes), nothing left behind, exit 1 (the parent: 0 bytes) | the original kept (21 bytes), exit 153 — and a `*.rubocop.tmp` **left behind** (the parent: 0 bytes) |
| SIGKILL on entry to the rename | the original kept, a `.codespell-*.tmp` left | the original kept, a `*.rubocop.tmp` left |

Against the prediction: thirteen of fourteen cells. The miss is RuboCop under `ulimit -f 0`:
predicted to leave nothing because an `ensure` removes the temporary file, it leaves one, because
Ruby dies on the signal (exit 153) and the `ensure` never runs. The original is intact either
way.

Both fixes close the reported window and neither loses what the truncating write kept, a second
hard link aside — which RuboCop's commit names and codespell's does not. Unlike the two fixes of
this shape measured before (ImageMagick 2026-09-06, terraform 2026-09-29), nothing here is worse
than what it replaced.

One reading that is not the fix's: the parent RuboCop, which renames nothing for the source file,
also exits 137 under the rename probe — its result cache is saved by a rename, after the source
file was written (`transcripts/fix/rubocop-base.txt`, the file already 19 bytes). In the fix's
transcript the file is still 21 bytes and the temporary holds the 19, so the rename killed there
is the source file's.

The first attempt at these four runs reached no explore: `measure.sh` removed the state
directory's parent and the engine makes only the leaf (`transcripts/fix/host-first-attempt-setup-error.txt`,
four `SETUP_ERROR`s). One line was added and all four re-run; the probes in that first attempt
agree with the second and are not kept.

## Found in passing

- **A gate script of this run's asked the wrong question.** `gate-rumdl.sh` passed `--config`
  to `preflight`, which takes flags only: `SETUP ERROR`, exit 3, twice
  (`transcripts/entry/first-attempt-wrong-flags.txt`). It was replaced by the 2026-09-28
  `entry.sh` and `toml2flags.py`, copied unchanged, which is what should have been used first.
- **pint under `ulimit -f 0` dies before the file is touched** (exit 153, 39 bytes unchanged).
  The explore's FAIL stands on the kill; the no-crash route was not found for it.
