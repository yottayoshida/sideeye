# Selection — 2026-10-02 gate-cleared-twelve

## What was chosen, and by whom

Nothing was chosen here. The 2026-09-28 shipped-v170 run screened 119 names, put nineteen through
its entry gate, and eighteen cleared; it explored six, and its `SELECTION.md` records the other
twelve as "attempted, stopped by this run's choice" — the novelty pre-scan costs about fifty
searches a tracker, so the shortlist was cut to six before it. This run takes **those twelve, all
of them**, and the one target that gate refused, rumdl, with the step its refusal named. There is
no candidate table because there were no candidates: the screen, the exclusion set, the linkage
probe and the gate are the 2026-09-28 run's, and its `SELECTION.md` is the text for all four.

| Target | Version (the box's `versions.txt`) | Linkage | 2026-09-28 gate row |
|---|---|---|---|
| alejandra | 4.0.0 | static | supervised; accepted, 2 operations |
| biome | 2.5.14 | dynamic | accepted, 3 operations |
| gofumpt | 0.12.0 | static | supervised; accepted, 6 operations |
| helm (`repo remove`) | 4.3.0 | static | supervised; accepted, 4 operations |
| jsonnetfmt | 0.22.0 (go-jsonnet) | static | supervised; accepted, 2 operations |
| ktfmt | 0.64 | dynamic (JVM) | accepted, 2 operations |
| oxfmt | 0.70.0 | dynamic (Node) | accepted, 2 operations |
| pg_format | 5.6 (Debian's pgformatter) | dynamic (Perl) | accepted, 2 operations |
| pint | 1.32.1 | dynamic (PHP) | accepted, 2 operations |
| scalafmt | 3.11.5 (native image) | dynamic | accepted, 3 operations |
| tombi | 1.5.6 | static | supervised; accepted, 3 operations |
| yamlfmt | 0.21.0 | static | supervised; accepted, 2 operations |
| rumdl | 0.2.77 | dynamic | **refused**: `--twice` found different bytes (its cache under the state directory) |

Rows are `../2026-09-28-shipped-v170/transcripts/entry-candidates.txt`, unchanged.

## Nothing was rejected, and what that costs

A slate with no rejections is what `../README.md` warns about. Here it is the point: the twelve
are the remainder of a slate that was already screened, taken whole so that no second choice is
made after the first six verdicts were known. What is lost is the pre-registration of *which*
tools — anyone reading this knows the six explored on 2026-09-28 all FAILed in one shape, and so
did the person who decided to run the other twelve. The predictions (`PREDICTION.md`) say as much:
twelve FAILs predicted, from the operation counts alone.

## The box and the engine

`sideeye-sv170`, the image the 2026-09-28 run built (its `apparatus/build.sh` and `Dockerfile`),
not rebuilt: image id `sha256:e13bee48…`, created 2026-09-28T00:10:46Z (`transcripts/host.txt`).
The engine is the released v1.7.0 the page's installer put there
(`transcripts/<target>/engine.txt`). `run.sh` and the defines are that run's, copied unchanged
(`cmp` against the original before the first run); `apparatus/host.sh` is new and is only the
docker command.

The tools are therefore at the versions pinned on 2026-09-28, four days old. Whether each has
released since is in `RESULTS.md`.

## Three departures from the rules, stated

- **Rule 14's order is not kept.** 2026-09-28 ran the novelty pre-scan before any explore. Here
  the explores ran first and each FAIL got its novelty check afterwards — the order the
  2026-09-22 run was faulted for. The pre-scan is the cost that stopped these twelve on
  2026-09-28, and it was not paid up front here either; the checks that were made are in
  `transcripts/receipts/`, each dated after the explores.
- **Rule 11 is measured after, not before.** Whether each tracker answers bug reports was read
  with the novelty check. pint's cannot be measured at all: laravel/pint has issues turned off,
  which is why 2026-09-28 dropped it. It is explored here anyway, with nowhere to report a FAIL.
- **No checker.** 2026-09-28 wrote a checker for each of its six, seen green and red before the
  run. These thirteen defines carry none, so every verdict is the built-in rule's — the rewritten
  file holds its old bytes or its new ones — and the evidence bundle says what it held instead.

## Two upstream fixes, measured in the same sitting

Not targets of this run's selection: codespell-project/codespell#4028 and rubocop/rubocop#15721
are the fixes that answered this project's 2026-09-16 reports (codespell#4025, rubocop#15720),
and neither had been measured. Each is run from source beside its parent commit, on the
2026-09-16 define (`apparatus/fix/`, `PREDICTION-fixes.md`).
