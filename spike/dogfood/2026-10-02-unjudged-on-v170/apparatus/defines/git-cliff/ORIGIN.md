# git-cliff — origin

Copied byte-for-byte from `spike/dogfood/2026-09-22-shipped-v160/apparatus/defines/git-cliff/`
(`seed.sh`, `sideeye.toml`). Already in this run's format. Not measured here.

## Tool and engine at the time

git-cliff 2.14.2, from PyPI into a venv, `2026-09-22-shipped-v160/apparatus/Dockerfile`
lines 29-30 and 38:

```
RUN python3 -m venv /opt/py \
    && /opt/py/bin/pip install --no-cache-dir commitizen==4.18.1 ast-grep-cli==0.45.3 git-cliff==2.14.2 > /tmp/pip.log 2>&1; \
ENV PATH=/opt/py/bin:$PATH
```

The seed needs `git` (line 9). The preflight transcript shows git-cliff warning that
`cliff.toml` is not found and using its default configuration; that is the define as written.

Engine: the released Sideeye v1.6.0 (`trace contract v18`), installed by the page's installer
at `/opt/se/sideeye-v1.6.0-aarch64-linux/sideeye` (`transcripts/entry/engine.txt`). Box run
with `--network none --cap-add SYS_PTRACE` (`transcripts/commands.txt`).

## Why it was not explored

It cleared the entry gate: `sideeye preflight --twice --oracle /usr/bin/strace`, default
observation mode, "recording accepted — 2 state-changing operation(s)", the oracle agreeing
on 2, two runs 2014 ms apart leaving equal state, one writing thread
(`transcripts/entry/git-cliff.preflight.txt`, `git-cliff.threads.txt`; row in
`transcripts/entry-candidates.txt`, `gate=0`). It was left out of the slate by that
campaign's choice — "this campaign asked for two or three" (`RESULTS.md`, `SELECTION.md`).
No refusal and no `unknown_reason` exist for it.

## Changed from the original

nothing. (`2026-09-28-shipped-v170/apparatus/run.sh` reads a define the same way
`2026-09-22-shipped-v160/apparatus/run.sh` does; see `../eslint/ORIGIN.md` for what differs
between the two scripts.)
