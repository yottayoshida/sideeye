# #988 — a trace a process closed names `--observe supervised`: Flyway and Salt on main and on the change

One box (`apparatus/Dockerfile`, `sideeye-r1029`: Debian trixie, OpenJDK 21.0.13, Flyway 13.11.1, Salt
3008.4's onedir, strace 6.13, linux/arm64) and two builds, `zig build -Dtarget=aarch64-linux-gnu` of
main at `3a27be61` and of this change, each mounted at `/se`. The defines are the 2026-10-25 run's
`flyway` and `salt-grains` (`spike/dogfood/2026-10-25-shipped-v1160/apparatus/defines/`) unchanged,
mounted at `/ap` and run by `apparatus/run.sh` from their own `seed.sh`, `--network none`, privileged
with its own cgroup namespace (the containment `--observe supervised` needs).

| Define | Build | Command | Answer | Transcript |
|---|---|---|---|---|
| flyway | main `3a27be61` | `preflight --twice --oracle` | UNKNOWN `unresolvable_path`; next: "This target does something Sideeye refuses by design …" | `transcripts/flyway.base.preflight.txt` |
| flyway | this change | `preflight --twice --oracle` | UNKNOWN `unresolvable_path`; next: "A process this run observed … closed the descriptor the shim writes its records through … Run the same command with --observe supervised …" | `transcripts/flyway.988.preflight.txt` |
| flyway | this change | `explore --oracle --observe supervised` | **PASS** 53/53, the oracle agreeing on 52 operations | `transcripts/flyway.988.explore.txt` |
| salt-grains | main `3a27be61` | `preflight --twice --oracle` | UNKNOWN `unresolvable_path`; next: "This target does something Sideeye refuses by design …" | `transcripts/salt-grains.base.preflight.txt` |
| salt-grains | this change | `preflight --twice --oracle` | UNKNOWN `unresolvable_path`; next names `--observe supervised`, as Flyway's | `transcripts/salt-grains.988.preflight.txt` |
| salt-grains | this change | `explore --oracle --observe supervised` | **FAIL** 1 of 3, crash point 2 of 2 | `transcripts/salt-grains.988.explore.txt` |

The default mode still refuses both: the shim stops recording when `close` takes its descriptor, which
is #941's (ADR 0013). What moved is the step, and following it reaches the verdicts the 2026-10-25 run
reached by naming the mode by hand.
