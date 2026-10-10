# Results — 2026-10-10 uv-threadpool (#686)

#686 asks for one bounded measurement: the thirteen Node targets it lists, with and without
`UV_THREADPOOL_SIZE=1` declared as apparatus, on the same engine, both results kept. 2026-10-09
follow-ups 3 and 4 measured the *with* side on the released **v1.10.0**, the variable set in the
environment; #686's comment says the *without* side was not re-run on v1.10.0. This run takes that
side, on v1.10.0, with the same defines and tool versions (`apparatus/Dockerfile`, a copy of
follow-ups 3's cut to these thirteen: Debian trixie's Node v20.19.2, Node 22.23.3 for lingui, Docker
Desktop on the maintainer's Apple-silicon machine, aarch64). Predictions were committed before any
run (`e0cf46b0`, `PREDICTIONS.md`).

`apparatus: env:` checks that a value is present and sets nothing (`docs/apparatus.md`), so the
declared form changes no engine behaviour: the *with* side here is three of follow-ups 3's defines
with the variable set by their `env.sh` and declared in their toml (`apparatus = ["env:UV_THREADPOOL_SIZE=1"]`),
to see the declared form accepted and the rebuilt box agree with 2026-10-09.

## Without (`apparatus/defines/none/`, `preflight`, the default mode, `--oracle`)

Each define is follow-ups 3's with its `UV_THREADPOOL_SIZE=1` line removed; nothing else changed. The
recording refuses before any world, so `preflight` sees the wall (`apparatus/run.sh` explores only a
define whose recording is accepted; none was).

**All thirteen refuse `multiple_threads_detected` at the recording** (`transcripts/summary.tsv`,
`transcripts/none/<define>/preflight.txt`).

## Both sides, one engine (v1.10.0)

| target | without (this run) | with one libuv thread (2026-10-09 follow-ups 3 and 4; three re-run here, declared) |
|---|---|---|
| joplin 3.7.1 `mknote` | `multiple_threads_detected` | **PASS** 49/49 |
| stylelint 17.15.0 `--fix` | `multiple_threads_detected` | **PASS** 6/6 — here, declared: PASS 6/6 |
| prettier 3.9.7 `--write` | `multiple_threads_detected` | **FAIL** 1/3 — here, declared: FAIL 1/3 |
| svgo 4.1.0 | `multiple_threads_detected` | **FAIL** 1/4 |
| npm 9.2.0 `pkg set` | `multiple_threads_detected` | **FAIL** 1/3 |
| eslint 10.11.0 `--fix` | `multiple_threads_detected` | **FAIL** 1/3 |
| dotenvx 2.32.4 `encrypt` | `multiple_threads_detected` | **FAIL** 1/5 |
| bibtex-tidy 1.15.1 | `multiple_threads_detected` | **FAIL** 1/3 |
| glTF-Transform 4.5.1 `weld` | `multiple_threads_detected` | **FAIL** 1/3 |
| lingui 6.9.0 `extract` | `multiple_threads_detected` | past the threads wall into `child_touched_state_dir` (the CLI runs `lingui-extract.js` as a child) |
| Bitwarden CLI 2026.8.0 | `multiple_threads_detected` | `multiple_threads_detected` — proper-lockfile's lock directory on the pool thread |
| vercel 62.2.0 `telemetry disable` | `multiple_threads_detected` | `multiple_threads_detected` — `mkdirp(VERCEL_DIR)` on the pool thread at the top of every command; here, declared: the same |
| gemini-cli 0.62.0 | `multiple_threads_detected` | `multiple_threads_detected` — the pool thread writes the home registry (`mcp add` at project scope is judged, follow-ups 4) |

**`UV_THREADPOOL_SIZE=1` moves ten of the thirteen off `multiple_threads_detected` on v1.10.0**: nine
to a verdict, lingui to the next wall. The other three have a second writer that is not the pool's
size: the reasons are follow-ups 4's `strace -f` readings (`spike/dogfood/2026-10-09-followups-4/`).

## The declared form

The three declared defines ran as predicted, none a SETUP ERROR: the report's `apparatus` line and the
JSON's `apparatus` field name `env:UV_THREADPOOL_SIZE=1`, and nothing is left in `apparatus_unchecked`.
vercel's refusal printed the `next` sentence this change replaces — that sentence named the README's
limit and no way past it.

## What this does not cover

- **The with side of ten targets was not re-run here.** Declaring the variable changes no engine
  behaviour, and the three re-run reproduced 2026-10-09's verdicts in the rebuilt box.
- **One machine, aarch64, the default mode.** A thread pool's size is the measured thing; Node on
  another CPU count or kernel was not tried.
- **Kept here:** every define's `summary.txt`, `preflight.txt` or `explore.txt` and `explore.json`,
  and `engine.txt` (which records whether the variable was set). The work directories and the seed
  logs (43 MB) were read in place and not committed.
