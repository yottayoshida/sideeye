# 0111 — A weekly build judges newer Zigs against the breakages already known

- **Status:** Accepted (2026-10-10)
- **Refs:** #698 (from the 2026-10-05 whole-product review); #782 (the move off the 0.16.0 pin);
  ADR 0001 (Zig, pinned); ADR 0061 (actions pinned by commit, Dependabot deferred).
- **Scope:** `.github/workflows/zig-ahead.yml`, `spike/zig-ahead.sh`, `spike/zig-ahead-known.tsv`,
  the `zig-ahead-judge` job in `.github/workflows/ci.yml`.

## Context

ADR 0001 pins Zig 0.16.0 and accepts that "the breakage arrives all at once at the upgrade rather
than continuously". Nothing looked ahead. Zig 0.17.0 shipped on 2026-10-01, Homebrew's `zig`
moved to it, and a source build with it stops at `build.zig:612` (`b.args` is gone) — measured on
2026-10-10, nine days later, while #698 was being planned (#782). The released assets and the
Homebrew formula were unaffected: the formula has installed the released build since its first
version, on the stated grounds that a from-source formula would break whenever Homebrew's `zig`
moved past the pin — which is what happened to a source build here.

A job that only builds against a newer Zig and goes red on failure would have been red from its
first run and stayed red until #782 lands; a second breakage arriving meanwhile — a release after
0.17, or master breaking somewhere else — would change nothing anyone sees, and a red that never
changes is read as the normal state.

## Decision

A scheduled workflow, `zig-ahead.yml`, builds and tests Sideeye weekly on Linux and macOS with
three Zigs, and `spike/zig-ahead.sh` judges each of the six lanes:

- **pinned** — the version `build.zig.zon` names — must build and pass its tests. It is the run's
  comparison: when every lane is red, this one says whether a new Zig broke Sideeye or the
  workflow broke itself.
- **latest** and **master** are judged against `spike/zig-ahead-known.tsv`, one row per breakage
  already known: the OS it is on (`linux`, `macos` or `*`), the release's MAJOR.MINOR or `master`,
  a text every compiler diagnostic of that breakage contains, and its issue. A lane is green when
  it builds and nothing is listed for it, or when it fails and every diagnostic is explained by a
  row. It is red on a diagnostic no row explains, on a failure with no diagnostic at all, on a row
  for a lane that now builds, on a row a failing lane's diagnostics no longer show, and — on the
  latest lane — on a row for a release that is no longer the latest, which would otherwise never
  be looked up again.

The details each answer a way the first draft could have gone quietly wrong. The key is
MAJOR.MINOR so a point release meets its minor's row rather than turning red over the same
breakage. Diagnostics are read as a set, not "the first error": once a breakage is past
`build.zig`, the executable, the shim and the test roots fail in parallel and the order they print
in changes from run to run. The OS is in the key because a release can break one OS's code alone,
and Linux does not analyse the macOS branches at all — which is also why there are macOS lanes,
and why the lanes run `zig build test` once `zig build` passes: a plain build analyses no test
block.

The first list holds the one breakage measured on 2026-10-10, for both lanes and both OSes:
`no field named 'args' in struct 'Build'` (#782), the only diagnostic Zig 0.17.0 and master
0.18.0-dev.131 print for the tree at that date, measured on macOS. While it stands, master's
deeper breakages are hidden behind it — Zig stops at `build.zig` before compiling anything else —
and they become visible when #782 lands. The change that lands #782 empties the list, and must
measure master and write its row then: once `build.zig` stops using `b.args`, master's row no
longer explains anything, and the next weekly run is red until it does.

The workflow never runs on a pull request and is not a required check, so it cannot stop a merge.
The judge's selftest and a parse check of the list run on every pull request (`zig-ahead-judge`
in `ci.yml`), so a judge that stopped going red, or a row that no longer parses, is caught on the
change that caused it rather than a week later.

Its red reaches someone by GitHub's documented behaviour — a failed scheduled run is mailed to
whoever last edited the cron line — which is not measured here. GitHub also disables a public
repository's schedule after 60 days without activity.

### Dependabot, which #698 asked to revisit

Still deferred. ADR 0061 named the condition — "if that becomes the binding problem" — and it has
not: the four actions the workflows use carry the same commit today as on the day ADR 0061
landed (2026-09-12), so no pin has been bumped by hand in four weeks. Dependabot does not watch
Zig releases either, which is what #698 is about.

## Alternatives considered

- **A `continue-on-error` job in `ci.yml` against master.** Every pull request would carry a red
  mark for #782 until it lands, and red would become the normal state on exactly the page people
  read.
- **Red until #782, as the reminder.** Gives up noticing anything new until then — the property
  #698 asks for.
- **Compare against the first error line only.** Order-dependent once the breakage is past
  `build.zig` (above).

## Consequences

- A release after 0.17 that does not build Sideeye turns the weekly run red even before #782
  lands, because the list has no row for it.
- `docs/cli.md`, where it tells a reader to build from source with the pinned Zig, names this
  workflow and the list instead of stating which newer versions build — a version written there
  would go stale with nothing to check it.
- Whoever fixes a listed breakage removes its row, or the run goes red to say so.
