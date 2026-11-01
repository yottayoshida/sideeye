# `[controls]` on the 2026-10-14 Alembic define (#943, ADR 0143)

Measured 2026-10-31 in the box `apparatus/` builds (Debian trixie from the 2026-10-14 snapshot, the
packages of `transcripts/versions.txt` — python3-alembic 1.13.2-4, python3-sqlalchemy 2.0.40),
linux/arm64 under Docker Desktop, with the engine built from this change for aarch64-linux-gnu.

    sh apparatus/host.sh transcripts <engine-dir>

`apparatus/sideeye.toml` is `spike/dogfood/2026-10-14-mechanisms/apparatus/defines/alembic/sideeye.toml`
with `[controls]` added; `apparatus/check.sh` is that define's checker with one loop added, writing its
four legs to `$SIDEEYE_LEGS`; `apparatus/control-{a,b,c,d}.sh` are that run's `legs.sh` `break_a` ..
`break_d`, one per file. The state is seeded by that run's own `seed.sh`.

`sideeye preflight --config apparatus/sideeye.toml --oracle /usr/bin/strace` (`transcripts/preflight.txt`,
`transcripts/preflight.json`), exit 0:

| control | word | red legs |
|---|---|---|
| baseline | `none` (checker exit 0) | — |
| a | `more_than_its_leg` | a, d |
| b | `only_its_leg` | b |
| c | `only_its_leg` | c |
| d | `only_its_leg` | d |

The hand-written run (`spike/dogfood/2026-10-14-mechanisms/transcripts/controls.txt`, lines 46–51) read
`a=FAIL … d=FAIL` for leg a's control and one red leg for each of the others: the same result, now
named. Leg a's control records a second revision beside the first, and the next `alembic upgrade head`
refuses it (`Requested revision r2 overlaps with other requested revisions r1`), so leg d is red too.

Every word, on both platforms, is `spike/check-controls.sh` (CI's Linux and macOS jobs).
