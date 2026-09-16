# 2026-09-16 — crossed walls: results

Five targets past a wall that turned them or their class away (`SELECTION.md`), explored with
the released v1.4.0 and once more each with main `d5911cd` (contract v18, not a release). As
root in a `--privileged` container on Linux aarch64, state on the container's filesystem.
Driver `apparatus/explore.sh`; transcripts and JSON reports in `transcripts/explore/`; the
predictions were committed before the run in `PREDICTIONS.md`.

| Target | Mode(s) | v1.4.0 | main `d5911cd` | Predicted | Known upstream |
|---|---|---|---|---|---|
| Bun 1.4.2 `bun add` | syscalls | **FAIL** 3/3 — `package.json` empty | FAIL 1/1, same world | PASS — **miss** | **yes**: oven-sh/bun#39689, open since 2026-08-19 |
| ninja 1.12.1 | syscalls | **FAIL** 3/3 on the built-in invariant over `out.txt`, the checker passing; a second define, `out.txt` scratch and a rebuild checker: PASS 3/3, which cannot fail on the rebuild in these worlds (below) | FAIL 1/1 (first define) | PASS — **miss**; the second define was written after the miss and is not scored | — (ninja rebuilds the output: measured without Sideeye) |
| markdownlint-cli 0.49.1 `--fix` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `README.md` empty | FAIL 1/1 | FAIL — hit | none in the searched results |
| google-java-format 1.36.1 `--replace` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `A.java` empty | FAIL 1/1 | FAIL — hit | none in the searched results |
| xz 5.8.1 `-T2` | wrappers ×3, syscalls ×1 | **PASS** 4/4, 19/19 worlds over 18 crash points — the checker's; the built-in invariant judged no path | PASS 1/1 | PASS — hit | — |

None of the five was refused at exploration on the wall its screen said it had crossed, which
is what `PREDICTIONS.md` named as falsifying the run's premise. main answered what v1.4.0
answered in all five: none of them depended on #539.

## Bun 1.4.2 — FAIL, the truncating rewrite, and already known

**Crash point 10 of 10, 3 of 3 runs, the same world under main.** Between the `open` and the
`write` of `package.json`: the file is empty, and the checker — adapted from cohort 2's, keeping its parse leg and its re-run leg and dropping the installed `package.json` comparison, the tarball precondition and the `timeout` — fails on its first leg,
`package.json does not parse — a torn manifest survived the crash`
(`transcripts/explore/bun.140.syscalls.*.txt`).

The screen's capture names the call: `openat(…/package.json, O_WRONLY|O_CREAT|O_TRUNC|O_LARGEFILE,
0664)` followed by one 125-byte `write` (`transcripts/probes/open-flags.txt`, lines 759–760 of
the capture, cut by `apparatus/excerpts.sh`). The `O_RDWR` open of the same file at line 182 is an earlier probe, not the
rewrite — reading it as the rewrite is where the prediction went wrong: it expected an
in-place overwrite whose new content is longer than the old, which no single kill can tear.

**Without Sideeye** (`apparatus/probe-ulimit.sh`, `transcripts/probes/ulimit.txt`): with a
6,070-byte `package.json` — larger than every other file the operation writes — and `ulimit
-f` at 1, 2, 4 and 8 blocks, `bun add` exits 1 and leaves `package.json` at exactly 512, 1024,
2048 and 4096 bytes, `bun.lock` written (390 bytes) and `node_modules/probe-dep` present. A
failed write tears the manifest too — a prefix at the limit rather than the empty file a kill
leaves — and Bun exits 1 without restoring it.

**Known upstream, with a fix open and not merged** (`apparatus/upstream-bun.sh`,
`transcripts/meta/bun-upstream.txt`). oven-sh/bun#39689 — titled for concurrency, *"Make
concurrent bun test and bun install processes safe on shared files"*, by `robobun` (association
`COLLABORATOR`), open and unmerged since 2026-08-19 — adds `File::write_file_atomically`
(*"writes a temporary file and renames it over the target"*) and lists *"package.json writers
converted: `write_target` (add, update, link, install pkg, audit fix, -g)"*. #39666 (open)
says *"A 0-byte `package.json` is what an interrupted in-place rewrite leaves behind"* and
*"The writers that can leave the file empty are made atomic in #39689"*; #39701 (open) is
*"Stacked on #39689"* and converts `bun init`. Bun's latest release is `bun-v1.4.2`, published
2026-09-05, which is the build measured. **Not reported.** Found through the search API
(`apparatus/novelty.sh`, `transcripts/meta/novelty.txt`).

What the run measured about the wall: under `--observe wrappers` Bun still refuses
`oracle_missed_operation` at operation 1 in both builds (the screen); under `--observe syscalls`
the raw `openat` is counted and Bun is judged — the first time Bun reaches a verdict here.

## ninja 1.12.1 — FAIL on an output ninja rebuilds

**First define** (`explore.sh`: the 2026-09-16 define with its clock race removed, and that
run's checker — ninja can read its build directory, `in.txt` intact): **FAIL 3/3**, crash point
3 of 7, the built-in atomicity invariant over `out.txt`, holding neither the old nor the new
content; the checker passed in every world. The operation there is `cp`'s, ninja's child:
`openat(out.txt, O_WRONLY|O_TRUNC)`, a refused `FICLONE`, and then `copy_file_range`, the call
that moves the bytes and that the report names as the `write` (`open-flags.txt`). The child's
operations hold crash-point addresses (contract v15), and the run was in a container where the
engine can make cgroups (#559), so ninja's `setpgid` child is judged rather than refused. No
report line says a cgroup was made; that part is inferred from the container.

**Does ninja repair it?** Measured without Sideeye. `out.txt` truncated by hand after the setup
(`apparatus/probe-ninja.sh` part 1, `transcripts/probes/ninja.txt`), and the build killed for real
after a stand-in `cp` truncated it: `pkill -KILL -x ninja`, the build's status 137, `out.txt` at 0
bytes, `.ninja_log` still holding only the setup's entry (`apparatus/probe-review.sh` part 2,
`transcripts/probes/review.txt`). Both times the next `ninja` says `recorded mtime of out.txt
older than most recent input in.txt` and rebuilds, and `out.txt` equals `in.txt` afterwards.
ninja compares the output's own mtime with its inputs first; the truncation made that mtime
newer, and the second comparison — the mtime ninja's log recorded for the output — is still
older than `in.txt`, so the edge is dirty. My expectation before measuring, that the fresh mtime
would make ninja skip it, was wrong. **`probe-ninja.sh`'s own part 2 did not kill ninja**: its
stand-in sent `SIGKILL` to its own process group, ninja runs each command in a group of its own,
and ninja exited 1 after a failed edge. The review of this record read that from the `rc=1`;
`probe-review.sh` is the measurement that replaces it.

**Second define** (`apparatus/explore-ninja-recovery.sh`): `--scratch out.txt` (ADR 0043) and a
checker whose claim is ninja's documented recovery — re-run `ninja`, then `out.txt` equals
`in.txt`. **PASS 3/3**, 8/8 worlds, `.ninja_log` under the history form, the report naming the
scratch declaration.

**That PASS cannot fail on the rebuild.** Every report says restore assigns timestamps, so in
every explored world `in.txt` is newer than the log's recorded mtime and ninja rebuilds whatever
state the crash left. The leg itself rejects a state ninja does not rebuild — `out.txt` emptied,
`in.txt` dated older than the output and the log's record, `ninja -n` saying `no work to do`,
the checker exiting 1 (`probe-review.sh` part 3) — but no explored world is such a state, and the
explorations' own pre-run falsification broke only `in.txt`. What shows ninja repairs its output
is the probe above, not this define. The first define's FAIL is the class `docs/target-classes.md`
already holds for git's `COMMIT_EDITMSG` and cargo's regenerated lockfile: a file the tool
itself rebuilds, judged by an invariant that cannot know that.

## markdownlint-cli 0.49.1 — FAIL, the truncating rewrite

**Crash point 2 of 2, 4 of 4 runs (three `wrappers`, one `syscalls`), the same under main.**
Between the `open` and the `write` of `README.md`: `README.md lost "Title" (0 bytes)`. The
capture: `openat(…/README.md, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` then one 60-byte write,
on the process's main thread.

**Without Sideeye, and without a crash**: `ulimit -f 0; markdownlint --fix README.md` prints
`Error: EFBIG: file too large, write` from `Object.writeFileSync` at `markdownlint.js:327`,
exits 4, and leaves `README.md` at **0 bytes** (61 before). Node does not die of `SIGXFSZ`; the
write fails and throws, after the truncation. A failed write is enough — measured here only as
`EFBIG` under a file-size limit. Whether a full disk does the same was not measured, and it may
not: the truncation frees the old blocks, so a rewrite no larger than the original can fit.

**The first Node target `docs/target-classes.md` records a verdict for**, after joplin's refusal and cohort 4's language exclusion.
What judges it is that `fs.writeFileSync` runs on the main thread: the three Node tools whose
writes go through the asynchronous API (prettier, svgo, `npm pkg set`) are refused on two
writing threads in both builds, neither of them the main thread — libuv's pool is the likely owner, as the joplin row says (`SELECTION.md`).

No report found in igorshubovych/markdownlint-cli (seven queries) or DavidAnson/markdownlint-cli2
(four), every result of each read — at most 42 for one query (`novelty.txt`). A differently worded
report would not have matched. Neither repository publishes an AI or LLM policy that was found; markdownlint-cli has no
CONTRIBUTING file at `CONTRIBUTING.md`, `.github/` or `docs/`. **Rule 3 is weak** (one sustained human committer, `SELECTION.md`).

## google-java-format 1.36.1 — FAIL, the truncating rewrite

**Crash point 2 of 2, 4 of 4, the same under main.** `A.java lost "public class A" (0 bytes)`.
The capture: `openat(…/A.java, O_WRONLY|O_CREAT|O_TRUNC, 0666)` then one 274-byte write, from
one of the JVM's 18 threads — the only one that writes the state (strace ties one more tid to
the directory, an `unlinkat` of `/tmp/hsperfdata_root/47` issued relative to it).

**Without Sideeye**: `ulimit -f 0` (with `-XX:-UsePerfData`, so the JVM writes no hsperfdata
file first) prints `A.java: could not write file: File too large` and leaves `A.java` at **0
bytes** (225 before). The same reach as markdownlint-cli, with the same limit on what was
measured: a failed write, as `EFBIG`, empties the source file.

**The first JVM target `docs/target-classes.md` records a verdict for.** No report found in six
queries, every result read, at most 9 (`novelty.txt`). CONTRIBUTING.md covers the
Google CLA for code and says larger contributions start in the issue tracker; no AI or LLM
policy is published.

## xz 5.8.1 — PASS

**19/19 worlds over 18 crash points, 4 of 4 runs and 1 under main.** `f.bin.xz` is created with
`O_EXCL` beside `f.bin`, written in 14 `write`s — every one from the process's first thread
while two worker threads compress — `fsync`ed, its directory `fsync`ed, closed, and only then
is `f.bin` unlinked (`open-flags.txt`).

**The PASS is the checker's.** Every report says `0 path(s) judged pre-or-post`: `f.bin.xz` is
created and `f.bin` removed, and neither is rewritten, so the built-in invariant had nothing to
judge — the verdict line's *"satisfied the built-in atomicity invariant"* is true of an empty
set. The checker accepts `f.bin` intact, or `f.bin` gone and an `f.bin.xz` that decompresses to
it. Only its first branch was falsified before the runs, and in the explorations the second ran
only in the baseline world, so every branch was falsified afterwards (`probe-review.sh` part 4):
a torn `f.bin`, a truncated and an empty `f.bin.xz` with `f.bin` gone, and neither file, all
rejected; the complete `.xz`, and a partial one beside an intact `f.bin`, accepted. That last is
accepted by design, and it has a cost the checker does not see: re-running the same command
beside it fails, `f.bin.xz: File exists`, status 1, the original intact. The contrast is lz4,
with the same pool and a worker that writes (`SELECTION.md`).

## The predictions, scored

Three of five verdicts as predicted (markdownlint-cli, google-java-format, xz), and main's
agreement with v1.4.0 as predicted. Two misses. Bun: I read the `O_RDWR` probe at line 182 as
the rewrite, and the rewrite is the truncating `open` at line 759. ninja: the prediction named
`out.txt` as `cp`'s and left it to the checker, and did not consider that the built-in invariant
judges it anyway. The second ninja define was written after that miss and is not scored.

## What this run settled beyond its targets

- **The truncating rewrite is in nine languages now.** The 2026-09-16 userview run found it in
  seven targets written in seven languages — Python, Ruby, PHP, C, C++, Haskell, Rust (that
  run's `RESULTS.md` says four languages at line 34, its CHANGELOG entry and BUILDLOG say seven);
  this run adds JavaScript (markdownlint-cli) and Java (google-java-format). Bun is Rust since 1.4
  (its row in `docs/target-classes.md`), so it adds a tool and not a language.
- **For two of these, a crash is not needed.** markdownlint-cli and google-java-format report
  the failed write and exit, and the file is already empty — `ulimit -f 0` shows it with
  nothing installed. That is the reproduction a maintainer can run. Which other failures do the
  same (a full disk) was not measured.
- **Node is two classes.** Synchronous `fs` calls on the main thread are judged; tools that
  write through the asynchronous API refuse on the writer count — two threads, neither the main
  one — and #539 does not order them.
- **ninja rebuilds an empty output even when its mtime is fresh**, because it also compares the
  mtime its log recorded for that output.

## Apparatus faults found during the run

- The 2026-09-16 ninja define's clock race (`SELECTION.md`).
- `gh search issues --repo R "a b"` sends one argument holding a space as a quoted phrase: the
  first novelty pass returned nothing for every query, and the same words through
  `gh api search/issues` returned 1,552 results for Bun. The first pass's empty output was
  overwritten by the API pass; `novelty.sh` records why.
- The search API allows 30 requests a minute; the API pass hit it at the 16th query and the
  rest came back as errors. `novelty.sh` waits 2.5 s per query and the recorded pass has none.
- The explore driver printed each transcript's first line as the verdict, and for Bun and ninja
  that line is the target's own output or the checker's pre-run falsification (`falsify: …`),
  so the running summary (`transcripts/explore/explore-summary.txt`) does not show their verdicts;
  the verdicts above are read from each transcript's `PASS`/`FAIL` line and its JSON report.
- The first rule-11 reading and the first metadata record (`SELECTION.md`; the metadata pass
  carried a jq flag gh does not have and was retaken as `apparatus/repo-meta.sh`).

And what the first review of this record caught, each re-measured by `apparatus/probe-review.sh`
or retaken, and corrected on every page:

- `probe-ninja.sh` part 2 did not kill ninja (above).
- lz4's thread count: the pages said four at 5,750,000 bytes, counted by a command whose output
  was not kept; the screen's own transcript and `probe-review.sh` say three. The size at which
  workers start had no transcript at all.
- The novelty pass read the first 8 results of each query while four queries had more (21, 42,
  42, 9); `novelty.sh` prints every result now. The Bun upstream details were written from pull
  requests read in the session and not recorded; `upstream-bun.sh` records them.
- *"a full disk (`ENOSPC`)"* was written with only `EFBIG` measured, and is withdrawn.
- ninja's second-define PASS was scored as a prediction hit and stated without the caveat that it
  cannot fail on the rebuild; xz's PASS was stated without saying it is the checker's alone.
- `open-flags.txt` was cut by hand and annotated a count its excerpt did not show; it is
  `excerpts.sh`'s output now, and it shows `cp`'s `copy_file_range`, which the first cut omitted.
- And one of mine inside the re-measurement: the first *"partial"* `f.bin.xz` in `probe-review.sh`
  was `head -c 200000` of a stream only 112,864 bytes long — the whole file — so the checker
  appeared to accept a partial stream with `f.bin` gone. Halved, it is rejected.

## Upstream

Not decided by this run. Candidates, if the owner's call is yes: markdownlint-cli and
google-java-format — no report in the searched results, a reproduction with nothing installed
(`ulimit -f 0`), and no AI or LLM policy found for either; markdownlint-cli with rule 3 weak.
Bun is known and has a fix open.
