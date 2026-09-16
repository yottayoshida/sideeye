# 2026-09-16 — crossed walls: selection

The brief: five targets, weighted to ones that are measurable **because a wall moved** — not
only targets an earlier record refused, but targets an earlier selection left out, and classes
a selection would leave out. Where the other dogfood runs pick tools the selection rules
admit and find out where the walls are, this one starts from the walls.

## Which build

Two, because the wall that moved last is merged and unreleased.

- **The released v1.4.0**: `sideeye-v1.4.0-aarch64-linux.tar.gz` from the GitHub release,
  sha256 `709057371894565cbfc368cd2cc3402282f65f453520acb5cb4e9a2fb5b08820`, matched against
  the digest the release publishes. Prints `sideeye 1.4.0 (trace contract v17)`. What a user
  has, and the build every verdict below is stated from.
- **main `d5911cd`** (#539 merged: contract v18, threads ordered by a recorded creation or
  join), cross-built with the release workflow's own flags: `zig build -Doptimize=ReleaseSafe
  -Dtarget=aarch64-linux-gnu.2.28`. Prints `sideeye 1.4.0 (trace contract v18)` — the version
  string is not bumped on main, and the contract number is what tells the two apart. Not a
  release; every line that used it says so.

Both on Linux in Docker (Debian trixie, aarch64), state and work on the container's own
filesystem (#528), **as root in a `--privileged` container** so the engine can make cgroups
(#559). No part of this run separates the default container's answer; ninja's row in
`docs/target-classes.md` already records that one.

## Where the candidates came from

| Source | Record | Candidates |
|---|---|---|
| Refused, and the wall has moved since the record | `docs/target-classes.md` refusal table | **Bun** — its row says the `--observe syscalls` half of its reading predates #542's second change; **zstd** — refused on two writing threads, the thing #539 moved; **ninja** — refused on a cgroup in a default container and on stdio past the flush under `wrappers`, and never run under `syscalls` in a container that can make cgroups |
| Left out before any run, by a wall forecast | `spike/cohort4/CANDIDATES-REJECTED.md` | 128 repositories out on language alone (Go, TypeScript, JavaScript, Shell, PHP, Java, …); **yadm** on a child-process forecast |
| Left out by a measured screen | `spike/dogfood/2026-09-06-userview-2/SELECTION.md` | sqlfluff, libvips, zstd, ansible, bundler for threads — every one measured since; **git-annex** (12 threads, 113 `execve`), screened for the language record only |
| Classes a screen would leave out today | this run | **Node** tools (the language cohort 4 excluded; the one Node target on record, joplin, refuses on its writer count); compressors with **thread pools** (pigz, lz4, xz) — dropped on a thread count before v16, and the pool threads are created and joined, the edges #539 records |

git-annex was not taken: it has no GitHub repository, so rules 1 and 11 have no instrument
here, and it was screened in 2026-09-06 for the language record rather than as a candidate.

## Rules 1–3 and 11, for the candidates met for the first time

`apparatus/repo-meta.sh` → `transcripts/meta/repos.txt`; `apparatus/rule11-github.py` →
`transcripts/meta/rule11.txt`. Commits are on the default branch since 2026-03-16; `100` is
the API's page limit, a floor.

| Candidate | ★ | Commits (6 mo) | Authors | Rule 11 (reports ≥ 7 days old, not by the repo's own people) | Taken |
|---|---|---|---|---|---|
| markdownlint-cli | 1,096 | 55 | DavidAnson 10, one other human, dependabot 44 | 2 of 4 answered within a day (DavidAnson) | ✅ — **rule 3 weak**: one sustained human committer |
| google-java-format | 6,192 | 80 | eamonnmcmanus 46, cpovirk 14, kluever 7, … | 3 of 4 answered (1.6, 8.9 and 25.0 days), 1 not — **every reply is from outside the project**; the instrument counts anyone but the reporter | ✅ |
| xz | 1,653 | 100 | Larhzu 94, four others with 1–2 | 3 of 4 answered by Larhzu within 2.2 days, the fourth after 9.1 | ✅ — **rule 3 weak**: one sustained committer |
| prettier | 52,333 | 100 | fisker 26, kovsu 7, … | none old enough in the 60 most recent items | screened (below) |
| svgo | 22,674 | 38 | TrySound 20, SethFalco 12, … | 0 of 2 (only two qualified) | screened (below) |
| npm (`npm pkg set`) | 10,117 | 100 | many | 1 of 4, from outside the project | screened (below) |
| lz4 | 12,069 | 32 | Cyan4973 22, Nicoshev 7 | 1 of 4 | screened (below) |
| pigz | 2,968 | **0** | — | — | ❌ **rule 2** — last push 2025-08-16 |
| yadm | 6,424 | **0** on `develop` | — | — | ❌ **rule 2** — cohort 4's child-process forecast is never tested |
| TypeScript (`tsc`) | 111,067 | 100 | many | — | ❌ — **not a Node target any more**: `typescript@latest` on npm is 7.0.2, and the repository's language is Go |

**Rule 3 is weak for two of the five taken, and they are measured anyway.** The question this
run asks is reach, the way the 2026-09-11 run re-met targets without re-selecting them. The
weakness belongs to any upstream report, and `RESULTS.md` carries it there.

**The first rule-11 reading was wrong, and the instrument was changed rather than the
reading.** As copied from the 2026-09-16 userview run, `rule11-github.py` read prettier's
four most recent issues as three unanswered — two of them two days old and filed by a core
member. The copy here skips issues younger than seven days and issues whose author is the
repository's owner, member or collaborator.

## The measured screen (rule 10), before the slate

Three passes, each a real writing operation under `strace -f -y` (which thread ids of which
process wrote the state, and `setsid`/`setpgid`), then `sideeye preflight --oracle strace`
under both builds and both observation modes. Transcripts: `transcripts/screen/`; scripts
`apparatus/screen.sh`, `screen2.sh`, `screen3.sh`.

| Candidate | Threads / processes | Writers (strace) | v1.4.0 wrappers | v1.4.0 syscalls | main wrappers | main syscalls |
|---|---|---|---|---|---|---|
| **Bun 1.4.2** `bun add` | 6 / 1 | 1 tid | `oracle_missed_operation` (raw `openat`) | **accepted, 10 ops** | same as v1.4.0 | **accepted, 10 ops** |
| **ninja 1.12.1** (pass 2) | 0 / 3, one `setpgid` | ninja 1 tid, `cp` 1 tid | `oracle_missed_operation` (`.ninja_log` through stdio) | **accepted, 7 ops** | same | **accepted, 7 ops** |
| **markdownlint-cli 0.49.1** `--fix` | 10 / 1 | 1 tid (the main thread) | **accepted, 2 ops** | **accepted** | **accepted** | **accepted** |
| **google-java-format 1.36.1** `--replace` | 18 / 1 | 1 tid writes `A.java` | **accepted, 2 ops** | **accepted** | **accepted** | **accepted** |
| **xz 5.8.1** `-T2 --block-size=1MiB` | 2 / 1 | 1 tid (the main thread) | **accepted, 18 ops** | **accepted** | **accepted** | **accepted** |
| zstd 1.5.7 `--rm` | 4 / 1 | 2 tids | `oracle_missed_operation` | `multiple_threads_detected` | same | `multiple_threads_detected`, *"No thread creation or join the shim recorded orders the first of those before the second"* |
| lz4 1.10.0 `-T2 --rm`, 5,750,000 bytes (pass 2) | 3 / 1 | 2 tids | `oracle_missed_operation` | `multiple_threads_detected` | same | `multiple_threads_detected`, the same sentence |
| prettier 3.9.7 `--write` | 10 / 1 | 2 tids (neither the main one) | `multiple_threads_detected` | same | same, v18 sentence | same |
| svgo 4.1.0 | 10 / 1 | 2 tids | `multiple_threads_detected` | same | same | same |
| npm 9.2.0 `pkg set` | 10 / 1 | 2 tids write `package.json`* | `multiple_threads_detected` | same | same | same |
| git 2.47.3 commit that triggers automatic maintenance (pass 2) | 1 / 12, one `setsid` | several `git` processes write `.git`* (the maintenance child's repack among them) | `child_touched_state_dir` | same | same | same |

\* `screen-strace.py` matches a line when the state directory's path appears anywhere in it, so a
relative open whose directory descriptor names the state is counted as a write there — npm's
debug log and update-notifier stamp, and git's `open("/dev/null")`. The engine's own reading
in the same row is the one the refusal was drawn from.

What the screen produced that reading would not have:

- **Node splits on how the tool calls `fs`, not on Node.** markdownlint-cli's
  `fs.writeFileSync` runs on the main thread and is accepted in all four columns; prettier,
  svgo and npm write through the asynchronous API, and two threads write, neither of them the
  main one — joplin's shape, where libuv's pool is the likely owner, and the refusal under
  main says no creation or join the shim recorded orders them.
- **lz4 starts its workers only above 4 MiB.** 3,450,000 bytes under `-T2` start none;
  5,750,000 start four (`-B4` changes neither). The first pass measured a 1.1 MiB file, got
  `accepted` under `syscalls`, and was measuring a single-threaded lz4 without knowing it.
- **xz and lz4 have the same pool and opposite answers**: xz's main thread does every write
  and its workers only compress; lz4's main thread writes the frame header and end mark and a
  worker writes the blocks.
- **The ninja define the 2026-09-16 run used has a clock race.** Its setup builds, then
  rewrites `in.txt`, and ninja only rebuilds when `in.txt` is newer. In the same tick the
  operation has no work: the first pass recorded 4 operations under `wrappers` and **0 under
  `syscalls`** (`recording accepted, but nothing to explore`) from one image. `out.txt` is
  dated 2026-01-01 after the first build in pass 2's setup.

## The slate

| # | Target | Language | Wall it crossed | The single operation measured |
|---|---|---|---|---|
| 1 | Bun 1.4.2 | Rust (since 1.4) | raw `openat`, under `--observe syscalls` (#542) | `bun add --cwd <state> dep-1.0.0.tgz` (the 2026-09-11 define) |
| 2 | ninja 1.12.1 | C++ | the cgroup (#559) and stdio past the flush (`--observe syscalls`) | `ninja -C <state>` |
| 3 | markdownlint-cli 0.49.1 | JavaScript (Node 20.19.2) | the class: Node, excluded by language | `markdownlint --fix <state>/README.md` |
| 4 | google-java-format 1.36.1 | Java (OpenJDK 21.0.12) | the class: the JVM, excluded by language | `java … -jar gjf.jar --replace <state>/A.java` |
| 5 | xz 5.8.1 | C | a thread pool, excluded by thread count before v16 | `xz -q -T2 --block-size=1MiB <state>/f.bin` |
