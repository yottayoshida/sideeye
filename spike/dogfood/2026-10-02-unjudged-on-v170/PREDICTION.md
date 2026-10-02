# Prediction — 2026-10-02 unjudged-on-v170, committed before any explore ran

Thirty-one rows (`LEDGER.md`). Each is run two ways in the same box (`apparatus/Dockerfile`:
the 2026-09-28 box, the released v1.7.0, plus these targets' tools):

- **`run.sh`** — the page's path, the 2026-09-28 script unchanged: the default mode, then the
  one follow a refusal's own next step names (`--observe syscalls`, or `--observe supervised`
  for a `no_shim_marker` whose detail names it). This is what a user of v1.7.0 gets.
- **`modes.sh`** — all three observation modes asked for by name, one explore each, a FAIL
  replayed twice in its mode. This is what v1.7.0 can do.

Written from each target's record (`defines/<t>/ORIGIN.md`, the earlier `RESULTS.md`) and the
v1.7.0 changelog, with no run yet. "Sure" means the earlier record names a wall that no later
engine change addressed; "not sure" means a later change could have moved it. The run was
chosen to find out, so the predictions below should be wrong somewhere.

## A — cleared the 2026-09-22 gate, never explored (4)

| Target | Predicted | Why, how sure |
|---|---|---|
| git-cliff | FAIL | 2 operations on `CHANGELOG.md`: open-truncate then write, the shape of every formatter so far — fairly sure |
| js-beautify | FAIL | 3 operations, read as open, truncate, write (the biome shape) — not sure |
| ktlint | FAIL | 2 operations, a JVM `writeText` as ktfmt's — fairly sure |
| ormolu | FAIL | 3 operations; Haskell's `writeFile` opens with truncation — not sure |

## D — refused by an earlier engine (24)

Grouped by the wall on record.

**Static images (3)** — `no_shim_marker` in every mode but supervised. `run.sh`: the bare name
is refused with no mode named (the 2026-10-02 gate-cleared-twelve finding), so **UNKNOWN**
there unless the define names the image by path. `modes.sh` supervised: judged. 2026-09-27
judged all three PASS on an unreleased build, each "judging no file it wrote" — in the forms
measured then (`chezmoi --force`, `gopass rm`, lefthook with no checker).

| Target | `run.sh` | `modes.sh` supervised |
|---|---|---|
| chezmoi | UNKNOWN `no_shim_marker` | PASS, as 2026-09-27 — fairly sure |
| gopass | UNKNOWN `no_shim_marker` | PASS, as 2026-09-27 — fairly sure |
| lefthook | UNKNOWN `no_shim_marker` | PASS, as 2026-09-27 — fairly sure |

**Two writing threads of one process (10)** — `multiple_threads_detected`. Contract v18
(v1.5.0) judges threads a join orders; v1.7.0's supervised mode records creations and no
joins. A Node libuv pool or a compressor's worker threads are not joined before the write, so
the wall stands in all three modes.

| Target | Predicted, all modes | How sure |
|---|---|---|
| joplin | UNKNOWN `multiple_threads_detected` | sure — three campaigns, forty captures |
| Bitwarden | UNKNOWN `multiple_threads_detected` | sure |
| beets | UNKNOWN `multiple_threads_detected` | sure — pipeline siblings, 3/3 both modes |
| zstd (crossed-walls form) | wrappers `oracle_missed_operation`; syscalls and supervised `multiple_threads_detected` | sure |
| zstd (userview-3 form) | the same | sure |
| lz4 `-T2` | the same as zstd | sure |
| prettier | UNKNOWN `multiple_threads_detected` | sure |
| svgo | UNKNOWN `multiple_threads_detected` | sure |
| npm pkg set | UNKNOWN `multiple_threads_detected` | sure |
| eslint | UNKNOWN `multiple_threads_detected` | sure — at the gate on v1.6.0, the same engine rule |
| stylelint | UNKNOWN `multiple_threads_detected` | sure |

(Eleven rows: zstd is two defines.)

**Writes past the flush boundary (2)** — `oracle_missed_operation` under wrappers. v1.4.0's
`--observe syscalls` counts at the kernel boundary, and 2026-09-07 (`spike/followup-527/`, an
unreleased build at contract v14) judged both under it: metaflac PASS 13/13 over 12 crash
points, fontforge FAIL 183 of 185 over 184. Neither has been judged on a released engine. The
page's `run.sh` follows a next step that names syscalls.

| Target | `run.sh` | `modes.sh` |
|---|---|---|
| metaflac | wrappers refused, followed to syscalls: **PASS**, as 2026-09-07 — fairly sure | wrappers UNKNOWN; syscalls PASS; supervised PASS |
| fontforge | wrappers refused, followed to syscalls: **FAIL**, as 2026-09-07 — fairly sure | wrappers UNKNOWN; syscalls FAIL; supervised FAIL |

**The rest (8)**

| Target | Predicted | Why, how sure |
|---|---|---|
| mutool | UNKNOWN `unresolvable_path` in all modes | it unlinks the output before writing it; no engine change since addresses a path that is gone — sure |
| ocrmypdf | UNKNOWN `baseline_violates_invariant` in all modes | its output is not byte-repeatable even with the clock pinned — sure |
| bat | UNKNOWN `baseline_violates_invariant` in all modes | `metadata.yaml` differed between clean runs with the clock pinned — sure |
| meson | UNKNOWN `baseline_violates_invariant` in all modes | `meson-log.txt` is not byte-repeatable — sure |
| ccache | UNKNOWN `kill_did_not_land` in all modes | the only real target that refusal was met on; nothing since addresses it — fairly sure |
| fish | UNKNOWN `unsupported_syscall_observed` (inotify) in all modes | sure |
| vim | UNKNOWN `unsupported_syscall_observed` (getxattr) in all modes | sure |
| rrdtool | UNKNOWN `unsupported_syscall_observed` (a shared mapping) in all modes | sure. Its checker is red on the seed (`defines/rrdtool/ORIGIN.md`), so if the engine did judge, the checker would say FAIL for a reason that is not rrdtool's |
| git | UNKNOWN `child_touched_state_dir` in default and syscalls; **judged under supervised** | supervised was built for a child that leaves the group (ADR 0089) — not sure whether a detached maintenance child is that case |

## B — newer releases (3)

| Target | Predicted | Why |
|---|---|---|
| oxfmt 0.71.0 | FAIL, as 0.70.0 | the same `fs::write` line at the same place |
| pg_format v5.11 | FAIL, as 5.6 | the same `open '>'` |
| PHP-CS-Fixer v3.95.27, its own phar | FAIL, as through pint | the same `file_put_contents`; the phar is the one the project ships |

## Totals, as predicted

Of 31 rows under the page's path: 4 + 3 + 1 = 8 FAIL (A, B, fontforge), 1 PASS (metaflac),
3 UNKNOWN for want of a mode name (the static three), 19 UNKNOWN on a standing wall. Under
`modes.sh`: the static three become PASS and git may be judged, so 12 or 13 judged, 18 or 19
refused.

If this is right, v1.7.0 judges about a third of what earlier engines could not, and the two
biggest standing walls are threads (11 rows) and non-repeatable output (3 rows).
