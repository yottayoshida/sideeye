# What interposition reaches, and why the generated interposer is not built (#299)

**This directory is a frozen measurement record, not live tooling.** Nothing here is
maintained or run by CI; the commands below are the record of how the numbers were
taken, so a reader can retake them rather than trust them. It needs no entry in
`.gitattributes` or in `check-gitattributes.sh` for that reason (ADR 0021: a
subdirectory of `spike/` is documentation by default, and only a *live* directory —
one holding maintained code — has to be named in both).

Run on macOS 15.3.1, arm64, SIP enabled, unprivileged, 2026-08-31.

## The question

`#299` proposes generating the macOS interposer from libSystem's exported symbol table,
so that "exported by libSystem and touching a path or descriptor, but not wrapped"
becomes a mechanical diff that can be asserted empty in CI, rather than a class of bug
found one cohort at a time. It asks for three measurements before any design:

1. whether dyld interposition reaches calls resolved through `dlsym`, and calls made
   from inside libSystem to its own exports;
2. the size of libSystem's file-touching export surface, and what wrapping all of it
   costs at runtime;
3. a static `svc` scan's false-positive rate on real targets.

`#428` answered part of (2) — the size of the surface, not its cost. This record answers
(1) and closes the ticket on a decision about the rest.

## Measurement: the three edges of "calls that cross image boundaries"

`shim/src/macos.zig` states the mechanism the whole platform half rests on:

> A library declares pairs of (replacement, original) in a `__DATA,__interpose` section
> and dyld rewrites calls that **cross image boundaries**.

Three edges follow from that sentence. Two were already measured; the third was not.

| edge | reached? | measured by |
|---|---|---|
| the target calls libc directly | **yes** | assumed by every shipped CI leg, and the control in the run below |
| libSystem calls its own export internally | **no** | `docs/adr/0005-stdio-at-flush-granularity.md` ("the same probe on macOS shows dyld interposition equally blind to libSystem-internal calls"); re-measured for `mkstemp` on macOS in `spike/fsusage/phase0/RESULTS-mkstemp.md`, 2026-08-29 — two state-changing operations against one |
| the target resolves with `dlsym` and calls through the pointer | **yes** | this record |

### The third edge

`spike/toys/toy_reach.c` issues the same two state-changing calls, `mkdir` and `open`,
in five modes that differ **only** in how they are resolved: this image's own bindings,
`dlsym(RTLD_DEFAULT, …)`, `dlsym(RTLD_NEXT, …)`, `dlsym` on a handle from
`dlopen("/usr/lib/libSystem.B.dylib")` — the umbrella, which is what a program writes and
which re-exports rather than defines these symbols — and `dlsym` on a handle from
`dlopen("/usr/lib/system/libsystem_kernel.dylib")`, the image the symbols actually come
from. Five rather than one because the sentences this measurement feeds do not name a
form; the last is the one that could plausibly differ, and it was added after review
pointed out that "a scoped lookup" covers two things and only one was being run. The `write` and the
`close` are issued directly in every mode and are the in-run positive control: a run
that records nothing is a broken apparatus rather than a finding.

Two calls rather than one because `open` is variadic and `mkdir` is not. On arm64 those
conventions place arguments differently, so an effect appearing in only one of them
would be about the toy's calling convention; an effect in both would be about dyld.

Under `sideeye preflight` with the shim, all four modes:

| mode | `resolved_via` | `open` resolves in | `mkdir` resolves in | operations | file mode |
|---|---|---|---|---|---|
| direct | bound | `libsideeye_shim.dylib` | `libsideeye_shim.dylib` | 3 | 600 |
| default | RTLD_DEFAULT | `libsideeye_shim.dylib` | `libsideeye_shim.dylib` | 3 | 600 |
| next | RTLD_NEXT | `libsideeye_shim.dylib` | `libsideeye_shim.dylib` | 3 | 600 |
| handle | handle | `libsideeye_shim.dylib` | `libsideeye_shim.dylib` | 3 | 600 |
| defining | defining | `libsideeye_shim.dylib` | `libsideeye_shim.dylib` | 3 | 600 |

Unshimmed, every mode resolves both symbols in `libsystem_kernel.dylib` and creates the
same two entries. **dyld applies the interpose table to what a runtime lookup returns**,
and the two observations — an image name and an operation count — agree in all four.

The image name is reported rather than the addresses because two pointers being equal
says they are the same function, not which one, and ASLR makes the number unquotable.
The findings print to stderr because `preflight` relays the operation's stderr into its
own output and not its stdout — measured by moving the lines from one stream to the
other and watching them disappear.

**What this cannot show, and why that is the result rather than a gap.** It cannot
demonstrate that a mode took the branch its name says. Review broke an earlier version
of this instrument with a one-line mutant that forced the direct path in a run invoked
as `dlsym`, and nothing caught it — because once the answer is *yes*, every form returns
the same pointer and the arms become observationally identical. What is assertable is
the pair, and it is: the two calls resolve into the shim, while `getpid` — not wrapped by
the shim — resolves into `libsystem_kernel.dylib` in the same run. **That control is
matched on the reporter, not on the mode**: `getpid` is always looked up with
`RTLD_DEFAULT` whatever form the two calls used, because what it has to hold fixed is
`image_of`, which does not know how the pointer it was handed came to be. A reporter that
had stopped reading anything names the shim for all three and fails.

**Scope.** One machine, one OS build. The permission bits are checked because they are
the readable consequence of the variadic marshalling arriving intact.

## The two arguments against the generator that did not survive

Both were written into the plan for this change before the review round, and both are
wrong. They are kept here rather than deleted, because the ticket stays closed on a
decision and a reader is entitled to see that the decision is not resting on them.

**"The generator's input does not exist — the export table has no types, and the SDK
does not declare the `guarded_*` family."** The first half is true and the second is
not. `dyld_info -exports` prints `offset  symbol` and nothing else, but the SDK ships
`System/Library/Frameworks/Kernel.framework/Headers/sys/sysproto.h`, which carries
`struct guarded_open_np_args` with `path`, `guard`, `guardflags`, `flags` and `mode`
typed and named. The original search covered `usr/include` and reported on the SDK.

**"Wrapping every export still would not record `mkstemp`'s internal `open`, so the
equivalence the ticket leans on is false."** `mkstemp` is an export, so a generator
covering file-touching exports would wrap it and record the creation at that boundary.
What the mkstemp measurement establishes is narrower: wrapping `open` does not see the
call libSystem makes to it.

**Which export table, though, is the part that correction glosses.** `mkstemp` is
exported by `libsystem_c.dylib`, not by `libsystem_kernel.dylib` — the only table this
repository's tooling parses, and the one the counts above are taken from. `libSystem.B`
is an umbrella and exports three symbols of its own. So the correction holds against a
generator reading the whole re-export closure, and not against one built on the table
already in use here. That is a wider input than the ticket's phrase "libSystem's
exported symbol table" makes it sound, and it is part of what the cost measurements
would have had to price.

**And a number was wrong in the same draft.** It said 1548, from a second-column
extraction that took every architecture at once and kept the headings:

    $ dyld_info -exports /usr/lib/system/libsystem_kernel.dylib |
        awk 'NR>3 {print $2}' | sort -u | wc -l
    1548

Per architecture, keeping only underscore-led symbols:

    $ for a in x86_64 arm64 arm64e; do
        dyld_info -arch $a -exports /usr/lib/system/libsystem_kernel.dylib |
          awk 'NR>3 && $2 ~ /^_/ {print $2}' | sort -u | wc -l
      done
    1534      # x86_64
    1533      # arm64
    1533      # arm64e

**That is not the 1502 the checker prints below, and the difference is a filter rather
than a disagreement.** `check-macos-coverage.py` matches exports with `_(\w+)$`, which
cannot match a `$NOCANCEL` suffix — 31 of them on arm64 — and it dedups across
architectures. 1533 − 31 = 1502. Two commands, two definitions, and this is the one
place a reader would otherwise have to reconcile them alone.

## What carries the completeness claim instead, and how wide it is

Neither check claims the export namespace, and both say so themselves. Their own output
gives the denominators:

    $ python3 spike/check-macos-coverage.py shim/src/macos.zig shim/src/darwin_libc.zig
    watched 15 write-capable exports; 10 interposed, 5 excused with reasons;
    parsed 58 interpose entries and 1502 kernel exports

    $ python3 spike/check-fsusage-coverage.py src/fsusage.zig src/contract.zig shim/src/macos.zig
    ok   31 classified calls, all printable by this fs_usage and all interposed or explained;
         10 state-changing classes anchored

**15 watched against 1502 parsed** is the curated check's own statement that its ratchet
is over a list rather than over a namespace. The oracle comparison (`#428`) is anchored
differently — on what `fs_usage` can print and the classifier classifies, **31 calls** —
which is a real second observer rather than a longer list, and is the reason the macOS
half of the `#256` promise exists at all. It is still not the export namespace.

## Where this leaves #299

Closed as **not planned**. Not refuted: the generator's input exists in more places than
the first draft of this record could find, and nothing measured here says it could not
be built. What is declined is the price of finding out — measurements (2) and (3), the
runtime cost of bracketing a much larger wrapper set and a static scan's false-positive
rate on real targets, both of which only pay off if the design is taken.

The residual is named rather than closed. A call libSystem makes to its own export is
invisible to any wrapper set, generated or curated, because it does not cross an image
boundary — the second row of the table above. That is `#39`'s class, it is open, and it
is unaffected by anything decided here. On macOS what covers it is `--oracle-fs-usage`
(ADR 0031), which reads the syscall layer and does not care how the call was resolved;
without it a single-process run reaches a PASS only under `--allow-unverified`, and the
report says the weaker claim out loud.

The decision, and what it gives up, is recorded in the ADR beside this file.
