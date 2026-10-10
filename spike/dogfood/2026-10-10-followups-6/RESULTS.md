# Results — 2026-10-10 follow-ups 6

The eighth "おわり？". #687 asks first for a measurement — whether the static Go and Rust tools behind
`multiple_threads_detected` under `--observe supervised` have any order to record — and the comment posted
there on 2026-10-09 measured doctl, tofu, codex and tombi but said "jj was not re-measured". Measured here on
Jujutsu 0.44.0 (2026-09-27's) and 0.46.0 (the latest, 2026-10-07), with the released **v1.10.0** in one box
(`apparatus/Dockerfile`, aarch64 Linux). Predictions committed first (`08262142`; the third form's in
`74fbdb68`, written after the second form's runs and before its own; that commit was amended after the runs only to take the work directories out of the tree, its text unchanged).

Three forms of 2026-09-27's define (`apparatus/defines/jj-<version>-<form>/`), each `jj -R /s/jj/repo commit
-m probe` over a repository with one pinned commit (`initial`, holding `alpha`) and the reflog off, under the
same pins of jj's reproducibility environment:

- **plain**: `alpha` modified in the working copy, as on 2026-09-27; `jj commit` snapshots it itself.
- **snap**: the same, with `jj status` last in the seed, so the modification is already snapshotted — what any
  jj command does first.
- **del**: `alpha` deleted and the deletion snapshotted, so no tracked file is left in the working copy.

## Which threads write the repository

`strace -f` outside Sideeye (`apparatus/writers.sh`, `transcripts/writers/`), the same for both versions:

| form | threads or processes that changed `/s/jj/repo` |
|---|---|
| plain | **2**: the process's first thread (140 calls), and another thread of it (5 calls: a temporary in `.git/objects`, the `mkdirat` of its fan-out directory, the rename to the blob's name) |
| snap | **1** (83 calls) |
| del | **1** (83 calls) |

The second writer is the snapshot writing the modified file's blob into git's object store. The prediction
called it a rayon worker; strace shows only a thread of the same process, so that name is not measured. 2026-09-27
described the same pair — the main thread on `.jj`'s `working_copy`, another on a temporary in git's `objects`.

## The page's path

`explore` as `docs/ci-quickstart.md` runs it, then the next step it names (`apparatus/run.sh`,
`transcripts/explore/<define>/`). Every form refuses `no_shim_marker` first — the release binaries are static —
and its next step names `--observe supervised`, which was followed once:

| form | 0.44.0 | 0.46.0 |
|---|---|---|
| plain | UNKNOWN `multiple_threads_detected` | UNKNOWN `multiple_threads_detected` |
| snap | UNKNOWN `baseline_run_failed`, after 81 worlds; the oracle agreed on 81 operations and one thread wrote | the same |
| del | **PASS** 82/82 (81 crash points and the baseline), `oracle_verified` on 81 operations, the checker falsified before the run and run in all 82 worlds; one thread wrote | the same |

`preflight --twice --observe supervised` on the deletion form: accepted, 81 operations, "two runs 2013 ms apart
left equal state" (`transcripts/lab-6-*.txt`). The checker is 2026-09-27's with leg N changed to ask that the
probe commit list no files; on clean states it accepts the pre-state and the post-state and rejects a third
commit (`transcripts/del-checker-sanity.txt`).

## Why the snapshotted form refuses

The second row's prediction (PASS) was wrong. `preflight --twice` names the cause where explore does not
(`transcripts/lab-4.txt`): the two runs leave different bytes in `.jj/working_copy/tree_state`, a 6-byte field
at offset 12 of 48 — the file's modification time in milliseconds. Restore assigns timestamps during restore
(`docs/cli.md`, the `metadata` line), so in a restored world `alpha`'s time is not the one `jj status` recorded,
and jj re-reads the file and rewrites `tree_state`: 13 renames with the seed's time kept, 14 with `alpha` touched
(`transcripts/lab-5-keep.txt`, `lab-5-retime.txt`). The baseline world's trace is one operation longer than world
81's (14159 against 14095 bytes, 64 per operation, read from the work directory before it was moved out of the tree, as every run does): read as the engine stopping it at the operation index it was
armed with, 82, from the sizes and not from a decoded trace.

Ruled out first: jj failing on a restored state. The commit succeeds on a copy of the seeded repository with
its timestamps not kept and kept (`lab-1`, exit 0 each), on a retimed copy under strace with one writer
(`lab-2`), and on a copy of the files alone — empty directories dropped, default modes, new times (`lab-3`,
exit 0). The baseline did not fail; it did more than the recording.

**Not filed.** The answer is UNKNOWN, which is right; `docs/cli.md` says restore assigns timestamps, and says
`preflight --twice` is what compares a second run from the restored pre-state. What reads wrong is explore's
wording: "did not exit normally", and the next step "Change the define: the detail above names the declaration
this run contradicted" where the detail names none. That next step is the one #678 measured for permission
bits; this is the same shape for timestamps.

## Other trackers read for this round

- **ktlint/ktlint#3409**: a maintainer reproduced the defect on 2026-10-09 and left open whether it is worth
  fixing. Stage `acknowledged` (as of 2026-10-10). Nothing was asked, so nothing is answered (the 2026-09-14 rule).
- **mhx/dwarfs#388**: the fix branch's new commit is a rebase with the same change; nothing new to measure.
- **#697** (Intel macOS, musl, WSL2) stays unmeasured: each needs a machine this run does not have.

## What the round says

- **The thread wall in front of jj is the snapshot, not the commit.** When the commit has no file contents to
  write, one thread writes and jj is judged — PASS on both versions.
- **A tool that records file times is a second case of #678.** Restore's timestamps make the restored world do
  more than the recording, and explore says only that the baseline "did not exit normally". `preflight --twice`
  names the file and the bytes; the page's path never runs it.
- **A prediction about the verdict went wrong where the prediction about the writers held.** Reaching the
  judgement depended on a property of restore the prediction did not consider.
