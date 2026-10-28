# Scout brief — 2026-10-25 shipped-v1160

The owner's request, 2026-10-25: "sideeye dogfooding 新規（最新verで当てられるもの） 5OSS x 4セット" —
twenty tools this project has never met, which the released v1.16.0 can be pointed at, in four sets
of five. The conditions are 2026-10-12's (`../../2026-10-12-shipped-v1120/SELECTION.md`), moved to
v1.16.0:

1. **Fresh.** `sh apparatus/fresh.sh <name>` says `fresh`, and `sh apparatus/word-recheck.sh <name>`
   (run from the repository root) shows no whole-word hit that is this tool. The project is not in
   `apparatus/reported-repos.txt` (44 repositories this project has filed against): a second report
   to one of them is out.
2. **Reachable on v1.16.0.** Linux arm64, a CLI, a non-interactive command that changes an existing
   file or directory the user keeps, no network during that command. A static Go/Rust binary is fine
   (`--observe supervised`). Known walls (`docs/target-classes.md`, `docs/apparatus.md`): two threads
   of one process writing the judged directory with no one-thread switch, `fallocate`, a shared
   writable mapping of the state file, extended-attribute writes. v1.13.0–v1.16.0 newly let through:
   a directory renamed inside the state; `_FORTIFY_SOURCE` opens (`__open_2`) and `close_range`;
   calls that change nothing (`syncfs`, `sync_file_range`, an empty path); a tool that chdirs before
   it runs a helper; many children whose exec fails; non-ASCII paths. A candidate in one of those
   shapes is preferred, not required.
3. **Worth a bug.** At least 10,000 GitHub stars, pushed within six months, not archived, issues on,
   writing data a user would be hurt to lose. **Not a formatter or linter `--fix`** (measured many
   times). An embedded database's own file is allowed (DuckDB was taken on 2026-10-12).
4. Rule 11 of `spike/cohort4/SCOUT-BRIEF.md` is measured later by the run, not by the scout.
