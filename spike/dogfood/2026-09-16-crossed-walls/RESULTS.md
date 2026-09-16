# 2026-09-16 — crossed walls: results

Five targets past a wall that turned them or their class away (`SELECTION.md`), explored with
the released v1.4.0 and once more each with main `d5911cd` (contract v18, not a release). As
root in a `--privileged` container on Linux aarch64, state on the container's filesystem.
Driver `apparatus/explore.sh`; transcripts and JSON reports in `transcripts/explore/`; the
predictions were committed before the run in `PREDICTIONS.md`.

| Target | Mode(s) | v1.4.0 | main `d5911cd` | Predicted | Known upstream |
|---|---|---|---|---|---|
| Bun 1.4.2 `bun add` | syscalls | **FAIL** 3/3 — `package.json` empty | FAIL 1/1, same world | PASS — **miss** | **yes**: oven-sh/bun#39689, open since 2026-08-19 |
| ninja 1.12.1 | syscalls | **FAIL** 3/3 on the built-in invariant over `out.txt`, checker passed; **PASS** 3/3 with `out.txt` scratch and a rebuild checker | FAIL 1/1 (first define) | PASS — **miss** on the first define, hit on the second | — (not a defect: see below) |
| markdownlint-cli 0.49.1 `--fix` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `README.md` empty | FAIL 1/1 | FAIL — hit | no report found |
| google-java-format 1.36.1 `--replace` | wrappers ×3, syscalls ×1 | **FAIL** 4/4 — `A.java` empty | FAIL 1/1 | FAIL — hit | no report found |
| xz 5.8.1 `-T2` | wrappers ×3, syscalls ×1 | **PASS** 4/4, 19/19 worlds over 18 crash points | PASS 1/1 | PASS — hit | — |

None of the five was refused at exploration on the wall its screen said it had crossed, which
is what `PREDICTIONS.md` named as falsifying the run's premise. main answered what v1.4.0
answered in all five: none of them depended on #539.

## Bun 1.4.2 — FAIL, the truncating rewrite, and already known

**Crash point 10 of 10, 3 of 3 runs, the same world under main.** Between the `open` and the
`write` of `package.json`: the file is empty, and the cohort-2 checker fails on its first leg,
`package.json does not parse — a torn manifest survived the crash`
(`transcripts/explore/bun.140.syscalls.*.txt`).

The screen's capture names the call: `openat(…/package.json, O_WRONLY|O_CREAT|O_TRUNC|O_LARGEFILE,
0664)` followed by one 125-byte `write` (`transcripts/probes/open-flags.txt`, lines 759–760 of
the capture). The `O_RDWR` open of the same file at line 182 is an earlier probe, not the
rewrite — reading it as the rewrite is where the prediction went wrong: it expected an
in-place overwrite whose new content is longer than the old, which no single kill can tear.

**Without Sideeye** (`apparatus/probe-ulimit.sh`, `transcripts/probes/ulimit.txt`): with a
6,070-byte `package.json` — larger than every other file the operation writes — and `ulimit
-f` at 1, 2, 4 and 8 blocks, `bun add` exits 1 and leaves `package.json` at exactly 512, 1024,
2048 and 4096 bytes, `bun.lock` written (390 bytes) and `node_modules/probe-dep` present. A
failed write tears the manifest the same way a kill does; nothing in Bun kills it.

**Known upstream, with a fix open and not merged.** oven-sh/bun#39689 (by `robobun`, the
project's collaborator account, open since 2026-08-19) adds `File::write_file_atomically` —
temporary file and rename — and names `package.json` among the writers it converts; #39666
(open) says *"A 0-byte `package.json` is what an interrupted in-place rewrite leaves behind"*
and proposes that `bun install` refuse such a file instead of deleting the lockfile; #39701 (open,
stacked on #39689) converts `bun init`. None is in 1.4.2, the latest release. **Not reported.**
Searched through the search API (`apparatus/novelty.sh`, `transcripts/meta/novelty.txt`).

What the run measured about the wall: under `--observe wrappers` Bun still refuses
`oracle_missed_operation` at operation 1 in both builds (the screen); under `--observe syscalls`
the raw `openat` is counted and Bun is judged — the first time Bun reaches a verdict here.

## ninja 1.12.1 — FAIL on its output, PASS on what ninja promises

**First define** (`explore.sh`: the 2026-09-16 define with its clock race removed, and that
run's checker — ninja can read its build directory, `in.txt` intact): **FAIL 3/3**, crash point
3 of 7, the built-in atomicity invariant over `out.txt`, holding neither the old nor the new
content; the checker passed in every world. The operation there is `cp`'s, ninja's child:
`openat(out.txt, O_WRONLY|O_TRUNC)` and then its write (`open-flags.txt`). The child's
operations hold crash-point addresses (contract v15), and the engine made a cgroup for the run
(#559), so ninja's `setpgid` child is judged rather than refused.

**Does ninja repair it?** Measured without Sideeye, two ways (`apparatus/probe-ninja.sh`,
`transcripts/probes/ninja.txt`): `out.txt` truncated by hand after the setup, and the build
killed — ninja and a stand-in `cp` together — after the truncating open. Both times the next
`ninja` says `recorded mtime of out.txt older than most recent input in.txt` and rebuilds, and
`out.txt` equals `in.txt` afterwards. ninja decides from the mtime its build log recorded, not
the output file's own: an empty output with a fresh mtime is still rebuilt. My expectation
before measuring — that the fresh mtime would make ninja skip it — was wrong.

**Second define** (`apparatus/explore-ninja-recovery.sh`): `--scratch out.txt` (ADR 0043) and a
checker whose claim is ninja's documented recovery — re-run `ninja`, then `out.txt` equals
`in.txt`. **PASS 3/3**, 8/8 worlds, `.ninja_log` under the history form, the report naming the
scratch declaration. The first define's FAIL is the class `docs/target-classes.md` already
holds for git's `COMMIT_EDITMSG` and cargo's regenerated lockfile: a file the tool itself
rebuilds, judged by an invariant that cannot know that.

A caveat the second define carries: explored worlds restore with fresh timestamps, so in every
world `in.txt` is newer than the log's recorded mtime. The kill in `probe-ninja.sh` is what
shows the rebuild without that help.

## markdownlint-cli 0.49.1 — FAIL, the truncating rewrite

**Crash point 2 of 2, 4 of 4 runs (three `wrappers`, one `syscalls`), the same under main.**
Between the `open` and the `write` of `README.md`: `README.md lost "Title" (0 bytes)`. The
capture: `openat(…/README.md, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` then one 60-byte write,
on the process's main thread.

**Without Sideeye, and without a crash**: `ulimit -f 0; markdownlint --fix README.md` prints
`Error: EFBIG: file too large, write` from `Object.writeFileSync` at `markdownlint.js:327`,
exits 4, and leaves `README.md` at **0 bytes** (61 before). Node does not die of `SIGXFSZ`; the
write fails and throws. So a write that fails for any reason — a full disk (`ENOSPC`), a quota
— empties the file the user asked to have fixed.

**The first Node target `docs/target-classes.md` records a verdict for**, after joplin's refusal and cohort 4's language exclusion.
What judges it is that `fs.writeFileSync` runs on the main thread: the three Node tools whose
writes go through the asynchronous API (prettier, svgo, `npm pkg set`) are refused on two
writing threads in both builds, neither of them the main thread — libuv's pool is the likely owner, as the joplin row says (`SELECTION.md`).

No report found in igorshubovych/markdownlint-cli or DavidAnson/markdownlint-cli2
(`novelty.txt`). Neither repository publishes an AI or LLM policy that was found; markdownlint-cli has no
CONTRIBUTING file at `CONTRIBUTING.md`, `.github/` or `docs/`. **Rule 3 is weak** (one sustained human committer, `SELECTION.md`).

## google-java-format 1.36.1 — FAIL, the truncating rewrite

**Crash point 2 of 2, 4 of 4, the same under main.** `A.java lost "public class A" (0 bytes)`.
The capture: `openat(…/A.java, O_WRONLY|O_CREAT|O_TRUNC, 0666)` then one 274-byte write, from
one of the JVM's 18 threads — the only one that writes.

**Without Sideeye**: `ulimit -f 0` (with `-XX:-UsePerfData`, so the JVM writes no hsperfdata
file first) prints `A.java: could not write file: File too large` and leaves `A.java` at **0
bytes** (225 before). The same reach as markdownlint-cli: a failed write empties the source
file.

**The first JVM target `docs/target-classes.md` records a verdict for.** No report found (`novelty.txt`). CONTRIBUTING.md covers the
Google CLA for code and says larger contributions start in the issue tracker; no AI or LLM
policy is published.

## xz 5.8.1 — PASS

**19/19 worlds over 18 crash points, 4 of 4 runs and 1 under main.** `f.bin.xz` is created with
`O_EXCL` beside `f.bin`, written in 14 `write`s — every one from the process's first thread
while two worker threads compress — `fsync`ed, its directory `fsync`ed, closed, and only then
is `f.bin` unlinked (`open-flags.txt`). Every crash world holds either the original `f.bin` or
an `f.bin.xz` that decompresses to it. The contrast is lz4, with the same pool and a worker
that writes the blocks (`SELECTION.md`).

## The predictions, scored

Three of five verdicts as predicted (markdownlint-cli, google-java-format, xz), and main's
agreement with v1.4.0 as predicted. Two misses, both about reading a capture rather than about
the engine: Bun's rewrite was the truncating `open` at line 759 and not the `O_RDWR` probe at
182; and ninja's first define failed on an invariant the checker never sees, which the
prediction did not consider — its predicted PASS belongs to the second define, written after
the miss.

## What this run settled beyond its targets

- **The truncating rewrite is in nine languages now.** The 2026-09-16 userview run found it in
  seven (Python, Ruby, PHP, C, C++, Haskell, Rust); this run adds JavaScript (markdownlint-cli)
  and Java (google-java-format). Bun is Rust since 1.4 (its row in `docs/target-classes.md`),
  so it is a second Rust tool rather than a new language.
- **For two of these, a crash is not needed.** markdownlint-cli and google-java-format catch
  the failed write and exit, and the file is already empty — `ulimit -f 0` shows it with
  nothing installed. That is the reproduction a maintainer can run.
- **Node is two classes.** Synchronous `fs` calls on the main thread are judged; tools that
  write through the asynchronous API refuse on the writer count — two threads, neither the main
  one — and #539 does not order them.
- **An empty output with a fresh mtime is not stale to ninja**, because ninja compares against
  the mtime its log recorded.

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

## Upstream

Not decided by this run. Candidates, if the owner's call is yes: markdownlint-cli and
google-java-format — no report found, a reproduction with nothing installed, and no AI policy
published by either; markdownlint-cli with rule 3 weak. Bun is known and has a fix open.
