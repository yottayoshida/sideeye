# Selection — 2026-09-22 shipped-v160

The campaign the owner asked for once v1.6.0 was out: **two or three fresh, ordinary targets,
installed through the release asset and the quickstart path, carried from adoption to a
definitive PASS or FAIL with its evidence and report** — "not a hunt for many bugs, a check
that the release carrying the last few days' changes goes all the way on ordinary targets."
Three owner rulings shaped it and are recorded where they bite: explore runs the page's command
in the default mode and follows a next step naming `--observe syscalls` once; the entry gate's
visibility question is the installed engine's own preflight; candidates come from apt and from
version-pinned gem/pip/npm packages, at most twenty put through the gate.

## The exclusion set, declared before the candidates

`apparatus/fresh.sh` — the verdict-chain run's nine ledgers, copied, with its self-exclusion
(`mine`) pointed at this directory. Controls: `lefthook`, `overcommit`, `husky` and `detox`
come back **SEEN** (`transcripts/fresh-controls.txt`), and the selftest now asserts both that
the previous campaign's own target reads seen from here and that this run's `ast-grep` still
reads fresh after this run has written its rows (`transcripts/fresh-selftest.txt`, green).

## The screen

Sixty-nine names across three passes (`transcripts/fresh-screen-{1,2,3}.txt`), ordinary
command-line tools that rewrite a file in place or keep a state file.

| pass | names | fresh | seen |
|---|---|---|---|
| 1 — in-place formatters and editors | 36 | 15 | 21 |
| 2 — Node-free tools with ≥1,000 stars | 22 | 5 | 17 |
| 3 — PHP, Kotlin, Haskell, C | 11 | 3 | 8 |

Rules 1 and 2 of `spike/cohort4/SCOUT-BRIEF.md` (≥1,000 stars, activity within six months),
measured with `gh api` (`transcripts/stars.txt`), left nine. The fresh names that fell there:
recode (151), docformatter (598), flynt (732), mdformat (823), pycln (315), toml-fmt (86),
toml-sort (116), yamlfix (262), htmlbeautifier (373), rufo (938), sort-package-json (917),
towncrier (922) on stars; stylish-haskell (1,026) on activity — last push 2025-12-28; astyle
has no GitHub repository to measure. Pass 1 alone left three candidates over the star bar and
all three were Node, which rule 13 (not a single-language slate) turns away — hence passes 2
and 3.

**Two numbers, kept apart.** Sixty-nine names were screened — the funnel's `candidates`
column, which counts what a campaign screened before fixing its slate. Nine were put through
the entry gate — the unit the owner fixed the cap in.

## The entry gate — the installed engine's own answer

`apparatus/entry.sh`, in the v1.6.0 box, `--network none` (`transcripts/commands.txt`).
Static linkage by `file -L` on the operation's image; visibility and interior by **`sideeye
preflight --twice --oracle /usr/bin/strace`** of the installed v1.6.0, mapped to 0 / 1 / 2 by
its `next` sentence (the table is the script's header and ADR 0085's amendment); threads by
the verdict-chain gate's `gate_threads`, unchanged — the copy is `cmp`-identical, and its
selftest is 11 of 11 green (`transcripts/gate-selftest.txt`), run in the verdict-chain box
because its visibility leg needs lefthook, which this box does not carry. Every question is
preceded by the define's seed.

**The first gate run measured threads on the wrong state.** `gate.sh` reads `GATE_RESET` only
in `all`, not in `threads`, and `entry.sh` did not seed before calling it — so threads re-ran
each operation over preflight's output, which a formatter leaves already formatted, and five
of the seven it reached read "0 thread ids wrote" — a green that measured nothing. Found in
review; `entry.sh` now seeds before threads, and every gate row below is from the re-run
(`transcripts/entry-candidates.txt`; the first run, with its threads lines, is
`entry-candidates-first-run.txt`). No answer changed: each of the seven now reads one writing
thread.

What was seen, and on what (`transcripts/entry-legs.txt`, `transcripts/entry/`):

| mapping row | seen on | result |
|---|---|---|
| preflight 0, N ≥ 2 → 0 | `toys/write2.py` | 0, 2 operations |
| preflight 0, N < 2 → 1 interior | `toys/one.py` | 1, 1 operation |
| preflight 1, `--twice` differs → 1 | `toys/stamp.py` | 1 |
| preflight 2, next names `--observe syscalls` → 0, FOLLOW | `toys/rawwrite.py` (a raw `syscall(SYS_write)`) | 0, `oracle_missed_operation` |
| preflight 2, class wall → 1 | `toys/childwrite.py`; `toys/twothreads.py` | 1, `sequence_numbering_broken`; 1, `multiple_threads_detected` |
| preflight 2, "Change the define" → DEFINE | ktlint's first define (a candidate, not a toy) | DEFINE, `recording_run_failed` |
| preflight 3, the define's own → DEFINE | a `cwd` that does not exist | DEFINE, "the declared cwd could not be resolved" |
| preflight 3, otherwise → 2 | `write2` with the oracle binary missing | 2, "--oracle is not an executable file" |
| static → 1 | `/bin/busybox` (busybox-static) | 1 |
| threads > 1 writer → 1 | `toys/joinedthreads.py` — two threads, each joined before the next writes | 1: preflight accepts it (4 operations), then two thread ids wrote — a red the engine does not share (below) |

**The threads question is now stricter than the engine.** joinedthreads is a target the
engine judges — the joins order its two writers, so preflight accepts it — and the threads
question turns it away, because it counts writer thread ids without reading the order. Since
threads is asked only of what preflight accepted, its red can only ever be that
disagreement. No candidate met it (each of the seven had one writer); ADR 0085's amendment
records it for the next run to settle.

**Not seen on anything:** preflight 2 with an environment, shim-pair or retry sentence → 2;
2 with `unwrap_or_class_wall` or an account-boundary sentence → 1; 2 with
`operation_not_an_image` or `narrow_state` → DEFINE; an unmapped answer → 2. The static red
is on busybox rather than on the lefthook binary ADR 0085's rule 2 names, because this box
does not carry lefthook; lefthook's red on the visibility gate is in the selftest above. And
for a `#!` script the static question looks at the script, not its interpreter. Six
candidates are scripts — eslint, stylelint, js-beautify and `cz` named bare and found on
`PATH`, `todo.sh` and ktlint by absolute path — and every interpreter their first lines name,
with the `node`, `bash` and `java` those go on to run, is dynamically linked
(`transcripts/checkers-ktlint-interpreters.txt`), so no candidate's answer depended on it.

The candidates, each first with the define a user would write (`apparatus/defines/`):

| candidate | version | language | gate | preflight | threads |
|---|---|---|---|---|---|
| eslint `--fix` | 10.11.0 | Node | **1** | `multiple_threads_detected` | — |
| stylelint `--fix` | 17.15.0 | Node | **1** | `multiple_threads_detected` | — |
| js-beautify `-r` | 2.0.3 | Node | 0 | 3 operations | 1 writer |
| ast-grep `scan --update-all` | 0.45.3 | Rust | 0 | 2 operations | 1 writer |
| git-cliff `--prepend` | 2.14.2 | Rust | 0 | 2 operations | 1 writer |
| commitizen `cz bump --files-only` | 4.18.1 | Python | 0 | 4 operations | 1 writer |
| todo.txt-cli `add` | 2.14.0 | Shell | 0, FOLLOW | `oracle_missed_operation`, next names `--observe syscalls` | 1 writer |
| ktlint `-F` | 1.8.0 | Kotlin/JVM | 0 on the second define | first: `recording_run_failed` | 1 writer |
| ormolu `--mode inplace` | 0.7.2.0 (Debian) | Haskell | 0 | 3 operations | 1 writer |

The two reds are the joplin class: in eslint one thread opens `a.js` and another writes it;
in stylelint, the same for its temporary file `a.css.<n>` — preflight names the thread ids
and finds no creation or join that orders them (`transcripts/entry/eslint.preflight.txt`,
`stylelint.preflight.txt`; `docs/target-classes.md` has the row). **ktlint's first define**
ran `ktlint -F a.kt`; ktlint exits 1 on a violation it cannot auto-correct, and `a.kt` breaks its own `standard:filename` rule
(`transcripts/checkers-ktlint-interpreters.txt`). The refusal named the declaration the
recording contradicted; the fixture was renamed `Main.kt`, and `sideeye.r1.toml` keeps the
first.

## Receipts and the novelty pre-scan (rules 11 and 14)

`transcripts/receipts/`. todo.txt-cli's `bug` label stops in 2018, so its receipt is the last
ten issues of any label: the three with comments were answered by a project member within a
day, and v2.14.0 shipped 2026-09-01. commitizen's and ast-grep's recent bug reports, with
their comment counts, are in `bug-reports-and-median.txt`.

**The order was not the rule's.** Rule 14 is a veto applied before the slate. What ran before
the slate (03:49–03:50 UTC, the receipt files) was a short search — six terms, `atomic`,
`truncate`, `corrupt`, `crash`, `empty file`, `data loss` — none of whose hits is about an
interrupted write. The full pre-scan (`spike/cohort4/novelty-prescan.sh`, 51 terms, both controls green;
the `*.prescan.txt` and `*.novelty2.txt` receipts) ran at 03:55–04:01, **after the three
explores had finished** (`transcripts/timeline.txt`: 03:53:49–03:53:55), so it was run
knowing both FAILs. It found no report of an interrupted write on either tracker, so the
veto would not have fired; it was applied late, not skipped — and a veto applied after the
result is not the blind check rule 14 describes.

## The slate — owner sign-off 2026-09-22

**todo.txt-cli, commitizen, ast-grep** — Shell, Python, Rust; a task list, a project's
version files, source rewritten in place. todo.txt-cli is the one candidate whose gate answer
was the follow row, so it is the one that runs the product's next-step loop on a real target.
js-beautify, git-cliff, ktlint and ormolu cleared the gate and were left out of the slate; the
funnel records each as attempted, stopped by this campaign's choice.
