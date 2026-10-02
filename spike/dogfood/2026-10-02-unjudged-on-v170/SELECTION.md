# Selection — 2026-10-02 unjudged-on-v170

## What was chosen, and by whom

Nothing was chosen. `LEDGER.md` is the slate: every target in `spike/outcome-funnel.tsv` whose
furthest row in any campaign is `attempted` or `explored` — 28 of 98, read per target, not per
row — plus the three newer releases the morning's gate-cleared-twelve run recorded as not
measured. There is no candidate table, no screen and no gate: the targets were screened by the
runs that first met them, and the question here is one question asked of all of them at once —
**what does the released v1.7.0 say about the targets no campaign has judged?** (Not "no
engine": six of them were judged on unreleased builds outside any campaign — `RESULTS.md`.)

The 31 rows, by why they were never judged:

| Group | Rows | Why no verdict |
|---|---|---|
| A | 4 | cleared the 2026-09-22 entry gate on v1.6.0; that slate left them out |
| D | 24 | refused by an engine older than v1.7.0, and no campaign met them since |
| B | 3 | measured at an older version this morning; a newer release exists |

## Two measurements per row

- **`run.sh`** — the 2026-09-28 script, unchanged but for two `source` lines (below): the page's
  command, then the one follow a refusal's own `next_step` names. What a user of v1.7.0 gets.
- **`modes.sh`** — new: the three observation modes v1.7.0 has, each asked for by name, one
  explore each, a FAIL replayed twice in its own mode. What v1.7.0 can do. Tried first on three
  targets the morning's run had judged (biome FAIL, rumdl `--no-cache` PASS, alejandra static) and
  read back their known verdicts before any row here ran (`transcripts/modes-control/`).

## The box

`sideeye-uj170` (`apparatus/Dockerfile`): `FROM sideeye-sv170`, the 2026-09-28 box with the
released v1.7.0 installed by the page's installer, plus these targets' tools. Each tool at the
version the earlier run recorded — Debian trixie's package where that run used one, the same
release asset (sha256 printed at build) where it fetched one, the npm or pip version its
transcripts report where it installed unpinned. Five (ccache, fish, vim, rrdtool, zstd) have no
version on record from 2026-09-16; the box's `versions` line in `RESULTS.md` is what ran. Nothing
in the box touches the engine.

## The defines

`apparatus/defines/<t>/`: `seed.sh`, `sideeye.toml`, and where the earlier run had them,
`check.sh` and the helpers it called. Each was copied from the run that last met the target —
operation and seed unchanged in content, paths moved under `/s/<t>/` — and each carries an
`ORIGIN.md` naming the source file and lines, the tool's version and install line then, the
engine then, the refusal then, and what changed. Three readers each copied a third; the
operation line of every define was compared with its source by hand afterwards, and the 2026-09-22
six are byte-identical to that run's.

What the toml cannot carry — the environment the earlier drivers exported — is in two places.
`apparatus/env.sh`, sourced before every engine run, is the 2026-09-16 drivers' `HOME`, `TMPDIR`
and `XDG_*` under `/s/aux` (crossed-walls `screen.sh:29`, `screen2.sh:26`; outside-git
`screen.sh:32`), so npm's, git's and Bitwarden's own files land where they did then.
`defines/<t>/env.sh`, sourced after it where present, is what one target's runner set: bat's
pinned clock and `libfaketime` in `/etc/ld.so.preload`, ccache's `CCACHE_DIR`, meson's `CC`,
fish's `XDG_CONFIG_HOME`, chezmoi's `HOME`, gopass's `GOPASS_HOMEDIR` and its test passphrase. A
re-measurement that moved the environment as well as the engine could not say which changed a
result.

Two departures from "unchanged", each in its `ORIGIN.md`: fontforge's operation holds a `"`,
which the toml parser cannot carry, so it runs through the `exec` wrapper the 2026-09-06 run
itself used (the image becomes `/bin/sh`); and every `--setup` script became a `seed.sh`, which
`run.sh` runs before each engine invocation as the engine ran `--setup` once per invocation.

Each seed was run once in the box before any explore, and each `check.sh` once on its fresh
seed. One is red there: rrdtool's, whose pattern never matched the consolidated row `fetch`
prints (`defines/rrdtool/ORIGIN.md`). It is kept as it was, since the 2026-09-16 engine refused
before it ever ran; a verdict resting on it is not read as a verdict about rrdtool.

## Rules not kept

- **No prediction per mode for most rows.** `PREDICTION.md` predicts the wall and whether a
  mode moves it; for the twelve "sure" rows that is the same word three times.
- **Rule 14's order.** The four A rows and the three B rows FAIL; their novelty check
  (`transcripts/receipts/`) was read after the explores, as the morning's was.
- **No checker for A and B.** The 2026-09-22 and 2026-09-28 defines carried none; the verdict is
  the built-in rule's.
