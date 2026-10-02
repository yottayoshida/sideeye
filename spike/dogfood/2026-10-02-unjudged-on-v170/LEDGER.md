# Ledger — 2026-10-02 unjudged-on-v170

Written before anything was run. Every row gets a result or "dropped, and why" before this run
says it is finished; the count does not change after this file is committed.

**Where the rows come from.** `spike/outcome-funnel.tsv` at `5d1541f`, read per target across
every campaign: 28 of its 98 targets have no row past `attempted` or `explored` — no campaign
carried them to a verdict. The 2026-10-02 gate-cleared-twelve run took the twelve the
2026-09-28 gate left; it did not look further back. These are the rest.

## A — cleared an entry gate, never explored (4)

The 2026-09-22 shipped-v160 gate accepted them (`preflight --twice`, v1.6.0) and its slate left
them out.

| Target | Gate row, 2026-09-22 |
|---|---|
| git-cliff | accepted, 2 operations |
| js-beautify | accepted, 3 operations |
| ktlint | accepted on the second define, 2 operations |
| ormolu | accepted, 3 operations |

## D — refused by an earlier engine, never judged since (24)

Each is the last refusal on record. The engine that refused is older than v1.7.0 in every row,
and v1.7.0 has two modes most of these rows never met (`--observe syscalls` from v1.4.0,
`--observe supervised` from v1.7.0).

| Target | Last met | Refusal on record |
|---|---|---|
| chezmoi | 2026-09-05 (and 2026-09-27 on an unreleased build) | `no_shim_marker`, static |
| gopass | 2026-09-05 (and 2026-09-27 on an unreleased build) | `no_shim_marker`, static |
| lefthook | 2026-09-21 (and 2026-09-27 on an unreleased build) | `oracle_missed_operation`, static |
| metaflac | 2026-09-06 | `oracle_missed_operation`, a stdio write past the flush boundary |
| fontforge | 2026-09-06 | `oracle_missed_operation`, the same |
| mutool | 2026-09-06 | `unresolvable_path` |
| ocrmypdf | 2026-09-11 | `baseline_violates_invariant`, output not byte-repeatable |
| joplin | 2026-09-13 | `multiple_threads_detected` |
| Bitwarden | 2026-09-16 | `multiple_threads_detected` |
| beets | 2026-09-16 | `multiple_threads_detected` |
| zstd (two defines) | 2026-09-16 | `multiple_threads_detected`; `oracle_missed_operation` under wrappers |
| lz4 | 2026-09-16 | `multiple_threads_detected` |
| prettier | 2026-09-16 | two writing threads |
| svgo | 2026-09-16 | two writing threads |
| npm pkg set | 2026-09-16 | two writing threads |
| git | 2026-09-16 | `child_touched_state_dir` |
| bat | 2026-09-16 | `baseline_violates_invariant` |
| meson | 2026-09-16 | `baseline_violates_invariant` |
| ccache | 2026-09-16 | `kill_did_not_land` |
| fish | 2026-09-16 | `unsupported_syscall_observed` (inotify_add_watch) |
| vim | 2026-09-16 | `unsupported_syscall_observed` (getxattr) |
| rrdtool | 2026-09-16 | `unsupported_syscall_observed`, a shared mapping |
| eslint | 2026-09-22 | `multiple_threads_detected` at the gate |
| stylelint | 2026-09-22 | `multiple_threads_detected` at the gate |

## B — newer releases the morning's run recorded as not measured (3)

Not from the funnel: `../2026-10-02-gate-cleared-twelve/RESULTS.md` says of three targets that
a newer release exists and was not measured.

| Target | Measured this morning | Newer |
|---|---|---|
| oxfmt | 0.70.0 | 0.71.0 |
| pg_format | 5.6 (Debian) | v5.11 (upstream) |
| the PHP-CS-Fixer inside pint | v3.95.25, through pint 1.32.1 | v3.95.27, its own phar |

## Not in the ledger, and why

- **Upstream fixes not yet measured: none left.** Of the 26 reports in
  `spike/upstream-reports.tsv`, four were answered with a fix: himalaya (measured 2026-08,
  `spike/cohort4/himalaya-r2/upstream-fix/`), ImageMagick (three patches, measured
  2026-09-05 and -06), codespell and RuboCop (measured this morning). pyupgrade and qpdf show
  as closed-completed on GitHub and were declined, with no change to measure.
- **The 2026-09-28 screen's other hundred names** did not reach its gate; why is that run's
  `SELECTION.md`, and they are not re-screened here.

Thirty-one rows: 4 + 24 + 3.

## Corrections after the run

This file was written before anything ran and its rows stand. Three of its sentences were
wrong, found by the first review and by reading `docs/target-classes.md` to the end of its rows:

- "Each is the last refusal on record" and "never judged since" hold for campaigns in the
  funnel, not for every build: mutool was judged on 2026-09-08 (FAIL 16 of 16, syscalls),
  metaflac and fontforge on 2026-09-07, each on an unreleased build outside any campaign; its
  last refusal on record is that day's `oracle_missed_operation` under the default mode. The
  static three carry that note above; these three did not.
- "Four were answered with a fix" is five: hashicorp/terraform#39303 answers the terraform
  report and was measured on 2026-09-29 and again this morning. "None left" stands.
- The D table has 24 rows and zstd is one of them with two defines.
