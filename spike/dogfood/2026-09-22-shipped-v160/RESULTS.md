# 2026-09-22 — results: the shipped v1.6.0, on three ordinary targets

Host: macOS on Apple Silicon, Docker Desktop, `linux/arm64`, `debian:trixie-slim`. One box,
`apparatus/Dockerfile`: Sideeye installed by the page's installer, the nine candidates beside
it. The network is present in one step only, `docker build`, where the installer fetches the
release asset and the candidates are installed; every gate, explore, replay and evidence ran
afterwards with `--network none`, and `--cap-add SYS_PTRACE` for the oracle
(`transcripts/commands.txt`).

**The prediction was stamped, not committed.** `PREDICTION.md`'s sha256 and the time were
written to `transcripts/prediction.sha256` (`e874125e…`, 03:53:38Z) before the first explore,
and the committed file has those bytes. That stamp is a file this run wrote itself, so it is
the run's own word, not a third party's. `transcripts/timeline.txt` is the run's word too —
written during review, from the host modification times of the targets' outputs, which are
last writes, not first — and it puts the earliest at 03:53:49Z. The prediction was written
after the gate, with its answers in hand — which is why todo.txt-cli's default-mode line is
the one marked confident.

**Outcome: all three reached a definitive verdict.** Two FAILs, each reproduced twice by
`sideeye replay` and rendered by `sideeye evidence`; one PASS reached by following the step
the engine named. One report filed upstream, `ast-grep/ast-grep#2959`.

## How far each gated candidate got

| candidate | gate | explore | verdict | evidence and report | stopped at |
|---|---|---|---|---|---|
| commitizen 4.18.1 | 0 | default | FAIL | rendered; not filed | the report — owner, below |
| ast-grep 0.45.3 | 0 | default | FAIL | rendered; filed | nothing — the report is upstream's now |
| todo.txt-cli 2.14.0 | 0, FOLLOW | default, then `--observe syscalls` | UNKNOWN, then PASS | a PASS has none | nothing |
| js-beautify, git-cliff, ktlint, ormolu | 0 | not run | — | — | the slate: this campaign asked for two or three |
| eslint, stylelint | 1 | not run | — | — | the gate: `multiple_threads_detected` |

## Adoption, measured

```
install-sideeye: reading yottayoshida/sideeye release v1.6.0 (unauthenticated; …)
install-sideeye: sideeye-v1.6.0-aarch64-linux.tar.gz published digest sha256:86622c84…f483
install-sideeye: downloaded digest matches (86622c84…f483)
install-sideeye: sideeye 1.6.0 (trace contract v18)
```

- stdout was the binary's absolute path and nothing else (`/opt/se/sideeye-v1.6.0-aarch64-linux/sideeye`,
  `transcripts/install.txt`), and that path is the one every gate, explore and replay ran
  (`transcripts/*/engine.txt`; `transcripts/entry/engine.txt` is one of the nineteen the gate
  runs wrote, which were byte-identical).
- **The installer is the page's as it stands now, not byte-for-byte the one at the tag**:
  `build.sh` checks both and records both (`transcripts/build.txt`). They differ in two
  comment lines — `v1.5.0` became `v1.6.0` in the usage example and the platform note, in the
  pull request that moved the page's pin — and in nothing that runs.
- **Operations the page does not state: none.** What this box added is the box's own: the
  proxy CA this machine's network needs (the release-path run's finding, unchanged),
  `--work` on a mounted directory so the case and the evidence outlive the container, and
  `SYS_PTRACE` for strace.
- **Define revisions.** Nine candidates, nine first defines written the way a user writes a
  command; one revision. ktlint's `-F a.kt` exited 1 on its own `standard:filename` rule
  (`transcripts/checkers-ktlint-interpreters.txt`), and the refusal named the declaration it
  contradicted (the recording's exit status against the declared success status). Six
  candidates are `#!` scripts — eslint, stylelint, js-beautify and `cz` named bare and found
  on `PATH`, `todo.sh` and ktlint by absolute path — and none was refused for being one; the
  two refusals among them were threads. The shape the release-path run measured — *"Change
  the define"* twice, with no line named — did not occur.
- Each checker was falsified by the engine before its explore — every report says
  `falsified before the run (corrupted state -> check failed)`. The hand run on the
  pre-state, the post-state and an emptied state — 0 / 0 / 1 each — that is committed
  (`transcripts/checkers-ktlint-interpreters.txt`) was taken again during review, after the
  explores. Before them, by this run's account and without a transcript, ast-grep's first
  checker rejected a correct rewrite — its fix drops the semicolon (`var x = 1;` →
  `let x = 1`) — and was loosened; a checker mistake, not a define revision.
- The measured versions were the latest published: commitizen 4.18.1 and ast-grep 0.45.3 on
  PyPI, where the box installed them from, and todo.txt-cli v2.14.0 on GitHub. commitizen's
  latest GitHub release is v4.18.0; PyPI is ahead of it (`transcripts/latest-versions.txt`,
  queried during review — after the ast-grep report was posted, not before as the prediction
  said the re-measurement would be).

## What v1.6.0 put in front of the reader

| | commitizen | ast-grep | todo.txt-cli |
|---|---|---|---|
| `command_cwd` / declared | `/s/cz/repo` / true | `/s/sg/proj` / true | `/w` / false — `(none declared: Sideeye's own)` |
| `l0_judged_paths` (omitted) | 51 (0) | 2 (0) | 2 (0) |
| evidence bundle | rendered, rc 0 | rendered, rc 0 | not reached — a PASS has none |

All three reports carry both new fields, including todo.txt-cli's default-mode UNKNOWN, which
reached classification before it refused. commitizen's 51 judged paths are the repository
with its `.git`: the define's state is the project root, which is where `cz bump` works.

## commitizen 4.18.1 — FAIL, definitive, not filed

`cz bump --yes --files-only` in a repository with one commit past `v0.1.0`
(`transcripts/commitizen/`): **FAIL, 1 of 5 explored worlds, crash point 4 of 4 — after the
`open` of `pyproject.toml`, before its `write`**: `pyproject.toml` goes from 126 bytes to 0,
holding neither the old nor the new content, and commitizen itself then reads the project as
*"No project information in this project."* `oracle_verified`, strace agreeing on four
operations; replayed twice from the saved case, FAIL at crash point 4 both times; the evidence
bundle renders (`explore.evidence.md`). The current `main` writes the file the same way:
`self.file.write_text(tomlkit.dumps(document))` in `commitizen/providers/base_provider.py`
(read, not run).

**Not filed** (owner, 2026-09-22). In `cz bump`'s normal flow the file it rewrites is committed
— the bump is computed from the commits since the last tag — so `git checkout -- pyproject.toml`
restores it, and a report about git-recoverable `pyproject.toml` was called low value once
already (`python-poetry/poetry#11019`). `ulimit -f 0` does not show it either: the changelog is
written first and the size limit fails there, leaving `pyproject.toml` whole
(`transcripts/ulimit-repro.txt`).

## ast-grep 0.45.3 — FAIL, definitive, filed

`ast-grep scan --rule rule.yml --update-all a.js` (`transcripts/ast-grep/`): **FAIL, 1 of 3
explored worlds, crash point 2 of 2 — after the truncating `open` of `a.js`, before the
`write`**: 22 bytes to 0. `oracle_verified` over two operations; strace shows
`openat(AT_FDCWD, "a.js", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` and one `write`
(`transcripts/ast-grep/strace-a.js.txt`, lines from the explore's own oracle capture).
Replayed twice, FAIL at crash point 2 both times; the evidence renders. `ulimit -f 0` shows it without a crash: the write dies with `File size
limit exceeded` and `a.js` is left at 0 bytes (`transcripts/ulimit-repro.txt`). The current
`main` calls `std::fs::write(path, new_content)` in `rewrite_action`
(`crates/cli/src/print/interactive_print.rs`, line 64; read, not run).

**Filed as `ast-grep/ast-grep#2959`** (owner, 2026-09-22), text in `report-ast-grep.md`: 348
words counted the way the median was (split on single spaces; 363 on any whitespace),
against a median of 228 over the tracker's last twenty `bug`-labelled issues
(`transcripts/receipts/bug-reports-and-median.txt`, taken again during review, after
posting; the filed issue is not among the twenty).
The reason it clears the target gate that commitizen does not: `--update-all` is an option
that exists to rewrite the files it is pointed at, and a codemod runs over working trees with
uncommitted edits in them, which git does not bring back. The two reports of this shape filed
on 2026-09-16 — `codespell-project/codespell#4025` and `rubocop/rubocop#15720`, both
`git`-tracked source, both rewritten by an option that exists for that — were fixed upstream,
by pull requests merged 2026-09-21 and 2026-09-16. ast-grep's `CONTRIBUTING.md` points to its
website, whose contributing page asks a bug report for the `bug` label, the expected and
actual results and, preferably, a playground link — not applicable to a CLI's file write —
and states no rule on AI-written reports (it offers LLM-optimised documentation). **That page
was read after the report was posted**, not before as this project's rule asks; nothing in it
would have changed the report. The report says it was drafted with an AI assistant.

One sentence of the posted text is looser than the measurement: it says the process was
killed "at each syscall boundary". Sideeye kills at the boundaries of the operations it
counted on the state — two here, the `open` and the `write` — not at every system call the
process made. The conclusion it supports (the file is empty between those two) is unchanged.

## todo.txt-cli 2.14.0 — UNKNOWN, then PASS through the named step

`/opt/todo/todo.sh -d /s/todo/todo.cfg add buy-bread` over a two-task list
(`transcripts/todo.txt/`).

- **Default mode: UNKNOWN `oracle_missed_operation`**, as the gate had said: the oracle saw
  `write(1</s/todo/data/todo.txt>, "buy-bread\n", 10)` and the shim's account ended after two
  operations — bash's `echo >>` writes from inside libc, past the entry points the shim
  interposes. The next step named `--observe syscalls`.
- **Followed once: PASS, 4 of 4 explored worlds, 3 crash points**, `oracle_verified` (the
  strace of the judged run, agreeing on three operations), the checker — `todo.sh ls` still
  lists both earlier tasks — falsified first and run in every world. The report says what
  this PASS does not cover: `todo.txt` is judged by the history form, and **its appended tail
  is not judged** — a torn last line would not be seen here.
- The report counts 17 other processes and says none touched the state directory; which
  programs they were, it does not say.

## Against the prediction

| | predicted | measured |
|---|---|---|
| todo.txt-cli, default | UNKNOWN `oracle_missed_operation` (confident) | as predicted |
| todo.txt-cli, `--observe syscalls` | a verdict (not confident) | PASS |
| commitizen | a verdict (not confident) | FAIL |
| ast-grep | a verdict, FAIL if the write truncates (not confident) | FAIL, the truncating open |

**The sunset case did not occur.** No target the gate cleared was refused by explore in a
phase preflight runs; todo.txt-cli's refusal was the gate's own answer repeated, the row the
gate maps to FOLLOW. ADR 0085's rules stand.

## Limits

- One architecture: the aarch64 Linux asset, in a Docker Desktop VM. The x86_64 asset was
  started under emulation in a bare image — it prints its version
  (`transcripts/x86_64-start.txt`) — and not run against a target.
- One run of each explore; the FAILs' repetition is the two replays, not two explores.
- The proxy CA and `SYS_PTRACE` make this box something a hosted runner is not; what it
  measures is the procedure and the engine, not a runner's toolchain.
- Four candidates cleared the gate and were not run, by this campaign's choice; the gate's
  answer for them is a prediction about explore, not a measurement of it.
