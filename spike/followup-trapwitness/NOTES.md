# What a trapped write looks like to the oracle

Taken 2026-09-08 against `41b9a8b`, with the engine's own oracle flags
(`strace -f -y -e trace=%file,%desc,%process,setsid,setpgid`) wrapped around a run with
`SIDEEYE_OBSERVE=syscalls`. That combination is the one ADR 0052 decision 4 declined; these
captures are what it looks like when it is taken anyway.

## The pairing exists and is visible under the flags the engine already passes

Single process, `toy-fixed rotate` (`trapped-engine-flags.txt` against
`untrapped-engine-flags.txt`):

    53: write(3</tmp/m/state/key.json.tmp>, "key=2\n", 6) = 3
    54: --- SIGSYS {si_code=SYS_SECCOMP, si_syscall=__NR_write, ...} ---
    60: write(3</tmp/m/state/key.json.tmp>, "key=2\n", 6) = 6

The untrapped run of the same operation has that write once. **`SIGSYS` is printed without
asking**: `-e trace=` filters syscalls, not signals, so no flag change is needed to see it.
The refused call's return value is not the byte count (`= 3` against `= 6`) but nothing here
relies on that — the register's contents after a refused call are not promised.

## Two shapes, not one — measured with children running (`trapped-children.txt`)

With other processes interleaving, the refused call is split across an unfinished entry and
a resumption, and only then does the signal arrive:

    8:14  write(3</tmp/c/state/from-child-b.txt>, "b\n", 2 <unfinished ...>
    9:14  <... write resumed>)              = 3
   10:14  --- SIGSYS {si_code=SYS_SECCOMP, si_syscall=__NR_write, ...} ---
   19:14  write(900</tmp/c/t.bin>, ...) = 47        <- the handler's own record, out of scope
   91:14  write(3</tmp/c/state/from-child-b.txt>, "b\n", 2 <unfinished ...>   <- the re-issue

So a rule written as "the next line for that pid is the signal" is not enough: the same
call's own resumption comes first. What holds in both shapes is **per pid, the next line
that is either a syscall entry or a signal — allowing the resumption of the write itself —
is the `SIGSYS`**. And another process's lines fall between freely, so the scan has to be
per pid rather than positional in the file.

Between the signal and the re-issue sit the handler's own writes to the trace file. Those
are already out of scope for the oracle (the trace path is outside the judged directory),
but a rule that expects the re-issue to be the *next* in-scope line for the pid would still
have to skip them.

## Cost

`trapped-stdio-big.txt` is the same single-process operation captured whole, at 157 lines.
The pair that supports the ratio was taken later and with the engine itself, so that both
halves come from the same command with the same oracle flags:
`engine-capture-wrappers-stdio-big.txt` (98 lines) against
`engine-capture-syscalls-stdio-big.txt` (158). About 1.6x. A capture the size of
fontforge's (untrapped: 40187 lines) was not taken; 1.6x there is a prediction.

**The recording phase loses a run, and that is not a speedup.** `timing-old-vs-new.txt`
times the whole `explore` seven times per engine: medians 43 ms before and 44 ms after,
distributions overlapping. The saved run is one execution of a millisecond-scale toy while
both engines explore fifteen worlds. An earlier draft of this record and of the CHANGELOG
said "so it is faster" — written from the run count, before anything was timed.

## What was built from this

The rule that shipped is **not** the lookahead the section above describes. Pairing a
refusal with its re-issue needs all of: skipping the call's own resumption, skipping the
handler's out-of-scope record writes, and scanning per pid rather than by file position.
The implementation instead **retracts** — an in-scope write is appended as before, and
reading `--- SIGSYS ... si_code=SYS_SECCOMP ... ---` removes the entry that pid appended
last. The discriminator is `si_code` and not `si_syscall`: the entry being retracted was
restricted to the trapped family when it was appended, so the name would only repeat what
the append side established, and an older strace that prints a bare number there is read
the same way. Nothing has to be recognised as a re-issue, so none of those three conditions exist.
The paragraph above stands as a description of the capture, not of the code.

Files, all under `artifacts/`: `trapped-engine-flags.txt`, `untrapped-engine-flags.txt`,
`trapped-children.txt`, `trapped-stdio-big.txt`.

## What it bought, measured after the change

Same container, engines side by side (`artifacts/parity-old-vs-new.txt`). The stdio toys
that this mode exists for keep every number they had — `TOY_STDIO_BIG` PASS over 14 crash
points and 15 worlds, `TOY_STDIO_NOCLOSE` PASS over 6 and 7 — and gain the claim:
`oracle_verified` goes false to true and `oracle_verified_across_runs` is gone from the
report entirely.

`lbdb` is the target that needed both this and the v15 multi-process slice, and was refused
whichever one it asked for. It reaches a verdict now:
**PASS over 8 crash points, 9 worlds, `oracle_verified_subject_only`**
(`artifacts/lbdb-syscalls-transcript.txt`, `artifacts/lbdb-syscalls-report.json`).
The v15 admission fires — the report's `processes` line says the child's operations hold
crash-point addresses — where the same target under `41b9a8b` refused
`child_touched_state_dir` in both modes, naming the separate untrapped run in one of them.

**That run was made as root, and the reason is not this change.**
`artifacts/lbdb-nonroot-wall.txt` is the same command as an unprivileged user: it refuses
`state_unsnapshotable`, because `lbdb-fetchaddr` takes a dotlock — `m_inmail.<host>.<pid>`,
created mode `0000` — and a crash world killed before it is released leaves that file in
the state tree, where only a reader with `CAP_DAC_OVERRIDE` can open it. The engine's own
next step for that refusal already says `environment`, which is the correct reading. It is
a third wall, behind the two this change removed, and it belongs to the target's crashed
state rather than to either witness.
