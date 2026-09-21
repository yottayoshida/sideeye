# 2026-09-21 — results: the adoption path, on a real project

Host: macOS on Apple Silicon, Docker Desktop, `linux/arm64`, base image `debian:trixie-slim`.
Two images: `apparatus/Dockerfile` installs Sideeye (the adoption step), and
`apparatus/Dockerfile.probe` builds `FROM` it to add the five candidates Debian does not package.
**The verdict below came from the probe image**, which carries the same engine — the install
happens in the base and nothing rebuilds it. `transcripts/linkage-full.txt` records which image
answered, and the engine it named.
**Sideeye was not mounted.** It was installed by `docs/ci-quickstart/release/install-sideeye.sh`,
vendored into `apparatus/` and run at image build time exactly as `docs/ci-quickstart.md:7` tells
a project to run it. One target: `lefthook` 8,833 stars (`transcripts/stars.txt`). **Outcome: one named wall,
`oracle_missed_operation`.**

## The adoption step, measured

This is the part no earlier dogfood run has: every one of the fourteen mounted a release tarball
the operator had already unpacked.

```
install-sideeye: reading yottayoshida/sideeye release v1.5.0 (unauthenticated; …)
install-sideeye: sideeye-v1.5.0-aarch64-linux.tar.gz published digest sha256:f81c58a3eb…4815
install-sideeye: downloaded digest matches (f81c58a3eb…4815)
install-sideeye: sideeye 1.5.0 (trace contract v18)
```

- **stdout was the binary's absolute path and nothing else** — `/opt/se/sideeye-v1.5.0-aarch64-linux/sideeye`.
  The page claims this; it is checkable here because the build step splits the two streams into
  `/install.path` and `/install.log`. A `RUN` mixes them and the claim would have been unreadable.
- **The digest check ran and matched.** Not `--selftest`: the real fetch, against the digest
  GitHub publishes for that asset.
- **No Zig, no source checkout**, and the binary it produced answers
  `sideeye 1.5.0 (trace contract v18)`.
- **The verdict below came from that binary.** `explore.sh` reads `/install.path` rather than
  naming a path, and writes what it got to `transcripts/lefthook.engine.txt`. This matters
  because the report carries **no engine version** — only `contract_version: 18`, which a local
  build of main shares — so nothing inside the report could tell the two apart.

## Operations this run performed that `docs/ci-quickstart.md` does not mention

Four. The section exists so that "it worked" cannot be written over them.

1. **`curl` installed into the image.** Plain `debian:trixie-slim` has `tar` and `sha256sum` but
   not `curl` or `python3`; the script needs all four and says GitHub runners have them, which is
   true. This is the container failing to be a runner, **not a gap in the procedure**.
2. **The intercepting proxy's CA copied in.** Without it every HTTPS call in a container on this
   machine fails with `curl: (60) SSL certificate problem: self-signed certificate in
   certificate chain`. **Measured with a control in the same run**: `https://example.com` fails
   identically, and the certificate offered for `api.github.com` is issued by the corporate
   proxy's own CA rather than by a public one. The installer is not what is broken. **This is the one place the
   container stops being a faithful stand-in for a GitHub runner**, and it is the reason this run
   cannot say anything about the page's claim that a runner has what the script needs — a claim
   `quickstart-release.yml` already tests on both Linux and macOS.
3. **`cwd` added to the define.** Not in the page's template. Without it the recording run exits 1
   and the report says only *"Change the define"* — it does not say which line. Located by three
   controls in one run of one image (`apparatus/controls.sh`, output in
   `transcripts/controls.txt`), the third of which differs from the shipped define **only** by
   the `cwd` line — the script builds it by deleting that line and prints the result into the
   transcript, so "same define minus one line" is checkable rather than asserted:

   | control | result |
   |---|---|
   | A — `lefthook install` alone, no engine, no shim | `exit 0`, hook written |
   | B — the same command with only the shim preloaded | `exit 0`, `pre-commit` and `prepare-commit-msg` written |
   | C — the shipped define with the `cwd` line deleted, under the engine, `--observe syscalls` | `UNKNOWN recording_run_failed`, the operation exited 1 |

   B is what rules out the shim, and C is what names the line.
4. **The repository built outside the define, before the engine starts.** `cwd` is resolved
   *before* the state directory is made — deliberately: *"a define naming a directory that is not
   there must refuse before anything on disk has moved"* (`src/main.zig`). So a `cwd` that the
   define's own `setup` would create can never resolve, and a project whose operation must run
   inside a directory has to build that directory outside the define. The page does not say this
   and `docs/cli.md` names `--cwd` without giving its ordering.

Points 3 and 4 are the adoption cost this run actually found: **two rounds of "change the define"
with no line named, both about ordering the pages do not state.**

## The verdict

| target | stage reached | verdict | why it stopped |
|---|---|---|---|
| `lefthook` 1.13.6, 8,833★ | **attempted** | **UNKNOWN** `oracle_missed_operation` | statically linked: no dynamic linker to interpose through |

`attempted`, not `explored`: the funnel derives that from the report, and this report says
`"explored": 0`. The run reached a define and the engine ran against it — which is what
`attempted` means — and then refused before exploring any world.

Measured under `--observe syscalls` (`apparatus/explore.sh`), with `/usr/bin/strace` as the
oracle. The engine's own words: the oracle saw
`openat(AT_FDCWD</tmp/lh-repo>, "/tmp/lh-repo/.git/hooks/pre-commit", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0755)`
and **the shim's account ends after 0 operations**. `lefthook version` is **1.13.6**, and `file -bL` on the binary reads
`ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, Go BuildID=7MNGMM…`
while `ldd` says `not a dynamic executable` — both in `transcripts/linkage-full.txt`, read to the
end of the line this time.

Beside the refusal the report still carries `14 path(s) judged pre-or-post` and
`3 other process(es) observed; none touched the state directory` — it says what it did see. It is
`exit 2`, not a PASS.

**Rule 10 should have caught this before the run**, and `SELECTION.md` says why it did not: the
probe was executed and its output was not read past `ELF 64-bit LSB executable`. Linkage is classified
mechanically for the eight candidates the probe image carries (`transcripts/linkage-verdicts.txt`,
full `file` lines in `transcripts/linkage-full.txt`), which also shows `go` is static — so
`go mod init` was failing rule 10 twice over while only its thread count was written down. **Three
rows of the table are not covered by that**: `npm`, `remind` and `bibtool` were read in the run
image, and their `dynamic` rests on `transcripts/probe-batch2.txt`, where the `file` output is
truncated at the terminal width. Their dispositions do not turn on it — they fall on rules 8 and 1
— but the same "did not read to the end" is still there in three lines of this run's own record.

## What this run does not establish

- **Nothing about GitHub-hosted runners.** The CA in point 2 takes that question off the table
  here; `quickstart-release.yml` is where it is answered.
- **Nothing about the adoption path's reach.** One target, and it hit a wall that is about the
  target's linkage rather than about how Sideeye was installed. The installer did its job.
- **No upstream report.** The run produced no FAIL, so there is nothing to report and no
  judgement about novelty to make.
- **A fourth thing a run owes, which `spike/dogfood/README.md` does not list.** Adding a target
  to the funnel puts it in `count.py b2-selection`'s coverage check: every name the funnel holds
  must be excluded from the B2 candidate pool by `spike/unknown-rate/b2-exclusions.txt` or an
  alias. CI caught this one — `'lefthook' … is not covered` — after the funnel row was written
  and before it was merged. The README names three follow-ups; this is a fourth, and it only
  appears once a funnel row exists.
- **The funnel cannot hold the first leg.** Its earliest stage is `attempted` — "the target
  reached a define and the engine ran against it" — so a target that failed at *adoption* could
  not have a row at all. None did here, which is why `coverage` is `full` honestly: the slate is
  defined as the targets that cleared adoption, and `lefthook` cleared it. Reading
  "adoption → verdict → report" end to end still needs this page beside the funnel, not the
  funnel alone.
