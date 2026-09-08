# followup-522 — the wall was one `close` wide, and there was a second behind it

**What this is.** The measurement behind the change that closes #522 ("an unplaceable
operation is a refusal in the recording run and is silently dropped in an explored world").
The engine refused a whole run over the address of an operation ADR 0003 §2 excludes from
the crash points, and the same rule was missing from two of the three places a trace is
read. `mutool clean a.pdf a.pdf` is the target that made both visible.

Everything here ran on a **container-local filesystem** in the `spike/followup-527/`
box — a macOS bind mount raises `unresolvable_path` on its own (#528), which is the
confound that killed the first plan for this rule.

## The motivating refusal, in four arrangements

The engine at `main` `fd2a6a6`, before this change. `step0.sh` is the no-oracle half:

| Arrangement | Runs | Result |
|---|---|---|
| `explore --observe wrappers --oracle strace` | 1 | `unresolvable_path`, `unlinked-fd close fd:3` |
| `explore --observe syscalls --oracle strace` | 1 | the same |
| `explore` with no oracle (`--allow-unverified`) | 4 | the same, 4 of 4 (`artifacts/s0-noor-*.txt`) |
| `preflight` with no oracle | 2 | the same, 2 of 2 (`artifacts/s0-pf-*.txt`) |

**The oracle's two-run arrangement is not what produces it** — which is the question that
killed the previous attempt at this rule, where the motivating refusal appeared only in the
recording run of a two-run configuration.

Under `strace -y` (`spike/followup-527/artifacts/strace-mutool-fd3.txt`), after the
`unlinkat` that removes the file it still holds open, fd 3 receives fifteen `read`s and one
`close` and nothing else. Read-only calls are not recorded at all, so **the only recordable
operation on that descriptor is the close.**

## mutool, sixteen runs per arm

`mutool16.sh`, `ARM=before|after|after-syscalls`. The rule was registered in the plan before
the numbers arrived: before 0 of 16 reach a verdict, after **at least 14**.

| Arm | Result | Artifact |
|---|---|---|
| before (default mode) | **16/16 `UNKNOWN unresolvable_path`**, all `unlinked-fd close fd:3` | `artifacts/m16-before.log` |
| after (default mode) | **16/16 `UNKNOWN oracle_missed_operation`** — 0 reach a verdict, **below the registered 14** | `artifacts/m16-after.log` |
| after + `--observe syscalls` | **16/16 FAIL, 2 of 4 explored worlds, earliest crash point 2 of 3** | `artifacts/m16-after-sys.log` |

**The registered rule was not met, and that is recorded rather than re-scoped after the
fact.** The divergence in the middle arm is `write(4</…/a.pdf>, …, 563)` — mutool writes its
output from inside libc, which `--observe wrappers` declines by design (ADR 0005) and
`--observe syscalls` was built for. **The wall was two deep**: this change removes the first,
yesterday's removes the second, and the target is judged only with both. The plan's sentence
said "the run is not refused" and was narrowed to the refusal *ground* after this
measurement, which the plan and `BUILDLOG.md` both say.

The verdict is a real window: killed between the `unlink` and the `open` that recreates the
file, no name carries the document and nothing holds the old contents.

## The reds

`artifacts/mutation-m*.txt` — five engine mutations against the eight new acceptance cells.
The counts below are **over those eight cells only**. Two mutations also redden
pre-existing cells — **M2 two and M3 one**, all of them `#485`'s — and the artifacts are
unfiltered so those lines are in them. (Review round 1 said three and one; counting the raw
logs says two and one, and the logs are what these files hold.)

| Mutation | New cells red |
|---|---|
| M1 exemption removed (the old behaviour) | 6 |
| M2 exemption unconditional | 5 — and the world cell returns **`rc=1`: a verdict over a world that wrote bytes nothing can name** |
| M3 the rejected shim-side design (give the close an address) | 6 — including **`#405` going `rc=0 recording accepted`**, the alibi pollution the plan rejected it for |
| M4 the world check removed | **exactly 1** (the world cell) |
| M5 the run-B check removed | **exactly 1** (the run-B cell) |

Three more at unit level, in `src/contract.zig`'s tests: prefix-matching the kind
(`trace-closed-by-target` contains "close"), dropping the `.unresolved` class gate, and
weakening the predicate to `isKillPoint` alone.

## What this does not cover

- **macOS.** The `fsusage.zig` edit removes a test unreachable for `.close`; the acceptance
  suite is the Linux container and this measurement is Linux.
- **x86_64.** CI is the verifier.
- **Whether mutool's window is worth reporting upstream.** A separate call, per run.

**The mutation transcripts predate one later fix.** They name `/tmp/acc-cls/…`, without the
pid suffix the shipped section now uses (`CLS=/tmp/acc-cls.$$`, added after review found the
fixed path would let a second local run start from a killed world's leftovers). The change is
to the path only; the suite was re-run green after it (`artifacts/acceptance-new-cells.txt`),
and the mutations were not repeated for a rename.
