# calcurse — scout proposals (assisted, #118)

T0: 20260814T140947Z. Sources: `calcurse --help` (pinned 4.7.1), behavior
probes. No external repo-understanding service was needed. **Process note,
recorded honestly**: this file was formalized AFTER the define — the
why/what/where metadata existed at define time in the toml and checker
comments, but the loop skipped the separate proposal artifact the protocol
requires; the runlog and this admission are the correction.

## P1 — `-P --purge --filter-pattern <summary>` (IMPLEMENTED)

- argv: `calcurse -D <datadir> -C <confdir> -P --filter-pattern AdaMeeting`
- **why**: the help text names the window itself — "-P, --purge: Read items
  and write them back". A read-everything/write-everything-back pass over
  the data files is the class where an interruption destroys entries the
  operation never named (campaign 1's topydo counterexamples live in this
  class).
- **what property**: *purging one event conserves the others* — the
  bystander event's `apts` line survives, exactly once, in every crash
  world, and the untouched `todo` file stays byte-identical.
- **where from**: the help text's own description of `-P`; probe: purge
  over the same pre-state is byte-deterministic, and the `apts` line format
  is exact and anchorable.

## P2 — `-i <file>` import (recorded, not implemented first)

- **why**: import appends into `apts`. **what property**: conservation of
  existing entries through the import write. **where from**: the help text
  (`-i, --import <file>`). Deferred: P1 covers the same
  files with the sharper (rewrite) window.

## P3 — `-g --gc` garbage collector (recorded, not implemented)

- **why**: a cleanup writer. **what property**: interrupting cleanup must
  not damage live data. **where from**: the help text (`-g, --gc: Run the
  garbage collector`). Deferred for the same reason.
