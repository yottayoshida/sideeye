# ormolu — origin

Copied byte-for-byte from `spike/dogfood/2026-09-22-shipped-v160/apparatus/defines/ormolu/`
(`seed.sh`, `sideeye.toml`). Already in this run's format. Not measured here.

## Tool and engine at the time

ormolu 0.7.2.0, Debian trixie's package (`SELECTION.md` candidate table: "0.7.2.0 (Debian)"),
`2026-09-22-shipped-v160/apparatus/Dockerfile` lines 18-20:

```
RUN for p in nodejs npm openjdk-21-jre-headless ormolu; do \
      apt-get install -y --no-install-recommends "$p" >/tmp/apt-$p.log 2>&1 && echo "OK $p" || echo "MISSING $p"; \
    done | tee /tmp/apt-summary.txt
```

Engine: the released Sideeye v1.6.0 (`trace contract v18`), installed by the page's installer
at `/opt/se/sideeye-v1.6.0-aarch64-linux/sideeye` (`transcripts/entry/engine.txt`). Box run
with `--network none --cap-add SYS_PTRACE` (`transcripts/commands.txt`).

## Why it was not explored

It cleared the entry gate: `sideeye preflight --twice --oracle /usr/bin/strace`, default
observation mode, "recording accepted — 3 state-changing operation(s)", the oracle agreeing
on 3, two runs 2002 ms apart leaving equal state, one writing thread
(`transcripts/entry/ormolu.preflight.txt`, `ormolu.threads.txt`; row in
`transcripts/entry-candidates.txt`, `gate=0`). Left out of the slate by that campaign's
choice (`RESULTS.md`, `SELECTION.md`). No refusal and no `unknown_reason` exist for it.

## Changed from the original

nothing. (`2026-09-28-shipped-v170/apparatus/run.sh` reads a define the same way
`2026-09-22-shipped-v160/apparatus/run.sh` does; see `../eslint/ORIGIN.md` for what differs
between the two scripts.)
