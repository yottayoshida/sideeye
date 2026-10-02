# Prediction — 2026-10-02 gate-cleared-twelve, committed before any explore ran

The 2026-09-28 shipped-v170 run put nineteen tools through its entry gate, eighteen cleared, and
six were explored. The other twelve were "recorded in the funnel as attempted, stopped by this
run's choice" (`../2026-09-28-shipped-v170/SELECTION.md`): the novelty pre-scan is about fifty
searches per tracker, so the shortlist was cut to six before it. This run explores the twelve —
all of them, with no further choice — and takes the one refused target, rumdl, the step its
refusal named.

The engine, the box, `run.sh` and the defines are that run's, unchanged: the released v1.7.0 in
`sideeye-sv170`. Nothing here has been explored; what is known about each target is the gate's
row from 2026-09-28 (`transcripts/entry-candidates.txt` there): static or not, and how many
operations the preflight accepted. **No source was read for these predictions** — they are
written from the operation count and the language, and each says how sure it is.

None of the twelve defines carries a checker; 2026-09-28 wrote checkers for its six only. So a
verdict here is the built-in rule's: the rewritten file holds its old bytes or its new ones at
every crash point, or it does not. A FAIL's evidence bundle says what the file held and whether
the old bytes are anywhere else.

## The twelve

| Target | Linkage, mode | Gate operations | Predicted | Why, and how sure |
|---|---|---|---|---|
| alejandra 4.0.0 | static, supervised | 2 | FAIL | open that truncates, then one write (Rust `fs::write`) — fairly sure |
| jsonnetfmt 0.22.0 | static, supervised | 2 | FAIL | the same two-operation shape — fairly sure |
| yamlfmt 0.21.0 | static, supervised | 2 | FAIL | `os.WriteFile` — fairly sure |
| ktfmt 0.64 | dynamic (JVM) | 2 | FAIL | google-java-format did this on 2026-09-16 — fairly sure |
| oxfmt 0.70.0 | dynamic (Node) | 2 | FAIL | two operations — fairly sure of the shape, less sure the explore is accepted (Node) |
| pg_format 5.6 | dynamic (Perl) | 2 | FAIL | two operations — fairly sure |
| pint 1.32.1 | dynamic (PHP) | 2 | FAIL | `file_put_contents`, as phpcbf — fairly sure |
| biome 2.5.14 | dynamic | 3 | FAIL | three operations read as open, cut to zero, write — not sure |
| tombi 1.5.6 | static, supervised | 3 | FAIL | the same reading of three — not sure |
| scalafmt 3.11.5 | dynamic (native image) | 3 | FAIL | three operations; could as well be a temporary file and a rename, which would PASS — a guess |
| helm 4.3.0 `repo remove` | static, supervised | 4 | FAIL | `repositories.yaml` rewritten in place plus the cache files removed, the kubectl shape — not sure; a temporary file and a rename would PASS |
| gofumpt 0.12.0 | static, supervised | 6 | FAIL, old bytes kept elsewhere | six operations is gofmt's shape — a backup copy, then the file written in place. The seed gets shorter (blank lines removed), so either a truncating open or a write-then-truncate leaves a file that is neither; the backup should hold the original — not sure which of the two |

So: twelve verdicts, twelve FAIL, one of them (gofumpt) with the original recoverable. The four
marked not sure or a guess are where this is most likely wrong.

## rumdl

Refused at the gate on 2026-09-28: `preflight --twice` found different bytes, its own cache
inside the state directory. The step named was to pin or relocate it. `rumdl fmt --help` lists
`--no-cache`; the define `rumdl-nocache` adds that flag and nothing else. Predicted: the gate
accepts it, and the explore is **FAIL** on two operations — not sure of either half.

## What is read off the result

- For each target: the verdict, the mode, the crash point, what the file held, and whether the
  old bytes are elsewhere (the evidence bundle), each FAIL replayed twice by `run.sh`.
- Upstream is not decided here. A FAIL is first checked against the target's default branch and
  tracker, and whether to report is the owner's call per target.
