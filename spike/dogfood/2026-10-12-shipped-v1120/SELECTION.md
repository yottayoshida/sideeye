# 2026-10-12 shipped-v1120 — selection

The owner's three conditions, 2026-10-12:

1. **Newly reachable on v1.12.0** — a kind of target or a language this project has not measured,
   or one the changes since v1.10.0 (the release the last campaigns ran) let through.
2. **Worth finding a bug in** — an open-source tool with at least 10,000 stars, writing data a user
   would be hurt to lose.
3. **Not reported before by this project.** A tool tried earlier and left unmeasured may come back.

## What v1.11.0 and v1.12.0 let through

Read from `CHANGELOG.md`, the four changes that open a class rather than fix a verdict:

| Change | What it lets through |
|---|---|
| #678 (v1.11.0, ADR 0109) | restore carries permission bits: a target whose behaviour depends on a mode under the state |
| #753 (v1.11.0, ADR 0115) | a call made from another shared library's constructor reaches the real function: C++ libraries that start a `std::thread` or open a file at load time |
| #685 (v1.11.0, ADR 0108) | a static target whose dynamic child carried the shim name, crossed under `--observe supervised` |
| #796 (v1.12.0, ADR 0122) | under `--oracle-fs-usage` on macOS, a target that writes its standard output is judged |

#686 (v1.11.0, ADR 0113) also names, in the threads refusal itself, a tool's own switch for one
thread (`docs/apparatus.md`).

## How the ten were found

Twenty-six names were put to GitHub's API on 2026-10-12 for stars, language and last push, and each
was looked up in `spike/outcome-funnel.tsv` (259 targets measured before this run), in
`spike/upstream-reports.tsv` (43 filings) and in every earlier `SELECTION.md` by name.

| Target | ★ | Why it is in | Earlier record |
|---|---|---|---|
| KeePassXC (`keepassxc-cli`) | 29,180 | the password database; C++ and Qt (#753's shape); **tried and not measured** | cohort 2's probe: every KDBX save draws fresh salts and IVs (`spike/cohort2/probes/recheck-keepassxc.txt`) |
| sops | 23,374 | an encrypted secrets file rewritten in place; static Go | passed the 2026-09-06 screen and was not taken |
| ansible-vault (ansible) | 70,955 | the only plaintext copy of a secrets file, encrypted in place; Python | 2026-10-05: out as "a seen parent is a seen tool". ansible-core itself was judged on 2026-09-13 (`cgroup-559`, PASS 2/2 on a playbook's write); the vault's own write was never measured |
| rclone | 60,251 | `rclone.conf`, every remote's credentials; static Go | 2026-09-05: out as "a repository format suspected; not verified", which does not describe its config file |
| DuckDB | 42,114 | a database file; C++ that starts threads | none |
| yq | 16,073 | a hand-written manifest edited with `-i`; it copies the file's mode | passed the 2026-09-06 screen and was not taken |
| Crystal (`crystal tool format`) | 20,448 | **a language not measured before**; a source file rewritten in place | none |
| SwiftLint | 19,756 | **a language not measured before** (Swift); `--fix` rewrites source | 2026-09-28: deferred for the cost of a Swift toolchain on Linux |
| FreeCAD (`freecadcmd`) | 34,175 | a CAD document; C++ over Qt, Coin and OpenCASCADE (#753's shape) | 2026-10-05: counted in the bug-label screen, not measured |
| Bun | 96,201 | measured on 2026-09-16 (FAIL, already known as oven-sh/bun#39689); **rewritten since** — the repository's languages now read Rust 51 MB, C++ 12 MB — so the earlier verdict says nothing about 1.4.3 | 2026-09-16 crossed-walls |

The owner replaced PostgreSQL (22,362★; its data directory must be 0700, #678's case) with Bun:
PostgreSQL takes no reports on GitHub, which leaves no tracker to read for whether a finding there
would be fixed. Hono (32,489★) was proposed and is out: a web framework whose own code writes no
file a user keeps, so there is no state for a crash to tear; its CLI (`honojs/cli`, 364★) writes
only new files.

## Out, with the reason

| Name | ★ | Why |
|---|---|---|
| ruff | 50,005 | a formatter, a class measured many times (black, rustfmt, prettier); rayon's pool is the wall `docs/apparatus.md` records as not moved by `RAYON_NUM_THREADS` |
| Deno (`deno fmt`) | 108,756 | the same class; a tokio runtime |
| mise, starship, gh | 34,916 / 60,227 / 46,664 | what they write is settings a user can set again |
| restic, syncthing | 36,523 / 89,316 | concurrent writers and a long-running daemon |
| Flutter, Elixir | 179,814 / 26,685 | network on first run; the BEAM's threads have no switch to one |
| biome | 25,931 | measured on 2026-10-02 |
| lz4 | 11,000+ | the threads wall `-T1` does not move (`docs/apparatus.md`), and it writes a new file |

## Issue activity, 2026-07-14 to 2026-10-12 (asked by the owner)

Measured with GitHub's search API: issues opened, issues closed as completed, merged pull requests
not by a bot, the median days to close a completed issue, and of a sample of completed issues how
many a pull request or commit closed.

| Repository | Opened | Completed | Human PRs merged | Median days | Closed by a PR or commit |
|---|---|---|---|---|---|
| duckdb/duckdb | 759 | 570 | 1,566 | 3 | 21 of 30 |
| FreeCAD/FreeCAD | 833 | 636 | 938 | 3 | 17 of 30 |
| crystal-lang/crystal | 131 | 89 | 262 | 23 | 28 of 30 |
| ansible/ansible | 71 | 46 | 200 | 20 | 13 of 30 |
| rclone/rclone | 155 | 111 | 156 | 8 | 17 of 20 |
| mikefarah/yq | 25 | 23 | 25 | 42 | 15 of 20 |
| getsops/sops | 15 | 3 | 6 | 9 | 2 of 3 |
| realm/SwiftLint | 23 | 12 | 24 | 211 | 7 of 12 |
| keepassxreboot/keepassxc | 150 | 63 | 35 | 0 | 1 of 30 — questions and fixes already on the 2.8.0 branch, closed within hours |
| postgres/postgres | — | — | — | — | issues are off |

"Completed" is the tracker's word, not a fix: qpdf closed this project's report as completed and
declined the fix (`docs/found.md`).

## Builds

Each from its own latest release for linux/arm64 as GitHub and PyPI answered on 2026-10-12
(`apparatus/Dockerfile`): keepassxc-minimal 2.7.10 from Debian trixie (upstream's releases carry no
Linux arm64 binary; upstream is 2.7.12), sops 3.13.3, ansible-core 2.21.5, rclone 1.75.2, DuckDB
1.5.6, yq 4.54.1, Crystal 1.21.1, SwiftLint 0.65.1 with SourceKit from Swift 6.4.0's debian12 aarch64
toolchain, FreeCAD 1.1.4 (its aarch64 AppImage, extracted), Bun 1.4.3. Sideeye v1.12.0 through
`docs/ci-quickstart/release/install-sideeye.sh`, digest matched.

## Linkage, before the gate

From `file -L` (`transcripts/lab-1.txt`): static — sops, rclone, yq, Crystal; dynamic — keepassxc-cli,
DuckDB, Bun, SwiftLint, freecadcmd, Python.
