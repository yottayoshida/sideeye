# 0108 — A static parent whose child carried the shim is sent to `--observe supervised`, at the sites measured to cross

- **Status:** Accepted (2026-10-10)
- **Amends:** ADR 0069 decision 1 (`oracle_missed_operation`'s step), ADR 0076 (`child_touched_state_dir`'s
  shimmed-writer arm) and ADR 0090 decision 3 (which images `--observe supervised` is named for). Each carries
  a dated note pointing here.
- **Refs:** #685 (from the 2026-10-05 whole-product review); the records that met the shape —
  `spike/dogfood/2026-10-02-unjudged-on-v170/RESULTS.md` (lefthook 1.13.6),
  `spike/dogfood/2026-10-05-user-data-2/RESULTS.md` (aliyun-cli 3.5.1) and
  `spike/dogfood/2026-10-07-user-data-3/RESULTS.md` (roswell 26.02.116).
- **Scope:** `src/boundary.zig`, `src/contract.zig`, `src/main.zig`, `spike/toys/toy.c`, `spike/acceptance.sh`,
  `docs/report-schema.md`, `docs/cli.md`, `docs/mcp.md`, `src/mcp.zig`.

## Context

`docs/cli.md` says of `--observe supervised`: "A statically linked target, which the other two modes refuse as
`no_shim_marker`, is counted and reaches a verdict under this mode." ADR 0090 made that refusal name the mode.
It is not the only refusal a static target meets. When the static operation starts a dynamic child, the child
loads the shim and announces itself, the default gate (`no_shim_marker`) is satisfied by a shim that is not in
the operation, and the operation's own calls are recorded by nobody. What comes out then is decided by what
the parent and child did:

| target | refusal under the default mode | the step it named | under `--observe supervised`, named by hand |
|---|---|---|---|
| lefthook 1.13.6 `install` (starts git) | `oracle_missed_operation` (v1.7.0) | `observe_syscalls`, which refused again with the class wall | PASS 5/5 on v1.7.0 (`nothing_could_fail` on this build, ADR 0091) |
| aliyun-cli 3.5.1 `configure delete` (runs `uname`) | `oracle_missed_operation` (v1.8.0) | the same | PASS 7/7 |
| roswell 26.02.116 `ros config set` (starts SBCL) | `unresolvable_path`, kind `trace-closed-by-target` (v1.9.0) | `class_wall` | FAIL 1/3 |

Each record says a user on the page's path never learns the way past. The 2026-10-07 record adds that a fix
keyed on `oracle_missed_operation` alone would still send roswell away.

## Decision

1. **`NextStep.observe_supervised_static_parent`**, produced only by `boundary.staticParentNext(site_step,
   shape_measured)`. Its sentence opens on the reason — the operation's image is statically linked, so no
   shim can be loaded into it (read before the run, which `image.zig` never reports as what ran), and the records
   this run read came from a process it started or an image it replaced itself with — and then names `--observe supervised` with that mode's conditions in the words
   `observe_supervised` uses. It does not open on "Run the same command again", which the acceptance suite
   anchors to `observe_supervised`, and it names explore and preflight, not replay.
2. **The site keeps choosing (#274).** `staticParentNext` takes the step the site would have named and the
   site's own reading of the shape that was measured, and returns the new member only when, besides that
   shape, the mode is not `supervised`, the build can supervise (`supervise.available`, a compile-time fact —
   ADR 0069's reason for not asking the kernel), the image read before the recording (`rec_image`) is a
   statically linked 64-bit ELF (the predicate `noShimNextFor` uses, now one function), and the run is not a
   replay (`boundary.replaying`, set where a replay reads its case). Three sites call it:
   - `oracle_missed_operation`, where the first process to announce a shim (`trace.primary_pid`) is not the one
     strace saw start (`parsed.primary_pid`). A static image that execs a dynamic one keeps its pid, so it is not
     this shape and keeps `observe_syscalls`, as before; whether either mode gets past it was not measured (the
     filter `--observe syscalls` installs comes with the shim, after the exec, so what the static image did
     before it is unrecorded there too).
   - the recording run's `unresolvable_path`, where the refusing record's kind is `trace-closed-by-target`. The
     site refuses six other kinds; `--observe supervised` refuses an unlinked descriptor, a descriptor without a
     path and a link by descriptor for the same reasons (read in `supervise_linux.zig`, not run), while a trace the
     engine holds cannot be closed by the target. The site reads the kind alone, so a static image that exec'd a
     dynamic one which then closed the trace takes the step too: under supervised the trace is the engine's whoever
     would close it, and the sentence names "an image it replaced itself with".
   - `child_touched_state_dir` on its shimmed-writer arm, with the same pair of pids. Measured on a toy (a static
     parent fork-execs a shell that inherits the preload and writes the state, and both write); no real target
     has met it yet.
3. **Everywhere else the site's step stands.** A step that cannot work is worse than one that only points at the
   class (`childTouchedNext`, ADR 0076).

## Alternatives considered

- **Fix `missedOperationNext` alone** (#685's own "What to add"). roswell keeps the class wall.
- **Rewrite the step at the exit (`refuse.unknown`) for every refusal of a static operation whose step was the
  class wall, `observe_syscalls` or `unwrap_or_class_wall`, minus a list of reasons.** The first draft. One reason
  is raised from sites the mode crosses and from sites where it refuses the same way — `child_process_detected`
  from the containment watches, from the oracle's `CLONE_FS`/`unshare` and from a second run that replaced its
  image; `kill_did_not_land` from a numbering past the crash point — and a reason-keyed table cannot tell them
  apart (`refuse.zig`'s "one reason, several remedies"). Review found five such sites.
- **Refuse at the gate**: count the gate satisfied only when the operation's own pid announced a shim, so the
  shape becomes `no_shim_marker` and takes ADR 0090's step. The refusal's reason — a frozen machine field
  (`docs/contract-freeze.md`, surface 2) — would change for every such run, and a run whose static parent writes
  nothing while its dynamic child writes everything, which the gate lets through today, would be stopped at it —
  whether any such run reaches a verdict now was not measured. Changing only the step can be undone.
- **A 32-bit static image, a build without the mode, macOS.** That mode does not see i386-compat or x32 calls,
  or is not there (ADR 0090).

## Consequences

- One `NextStep` member; no `unknown_reason`, no report field, no `contract_version` change. `next_step` is not a
  closed set (ADR 0069, ADR 0090).
- `docs/report-schema.md` states the three sites and what keeps its step. Its "Four refusals … keep the class
  wall" paragraph gains the exception; `docs/cli.md`'s `--observe` entry, `docs/mcp.md` and the server's
  `observe` description say a static target can be sent to `--observe supervised` by a refusal other than
  `no_shim_marker`.
- The detail beside the `child_touched_state_dir` shape still says the shimmed writer "recorded nothing of its
  own", which is not true of a child whose records were counted as the first announcer's. The sentence was
  written for ADR 0076's shape; it is left to that refusal and recorded here.
- The unknown-rate apparatus (`spike/unknown-rate/launchers/bgroup.sh` and `spike/unknown-rate/count.py`) takes its second leg only on the
  syscalls sentence, so a static parent of this shape stops taking that leg — which would have refused again.
  Its verdict was UNKNOWN either way; the gap ADR 0090 opened for `no_shim_marker` widens by this shape.
- A replay of a case counted under the default is not sent on even when it meets this shape: its crash point is a
  number in the default's count. No acceptance leg drives that condition: a case of this shape is saved where it
  reaches a verdict, under `--observe supervised`, and a replay of it is excluded by the mode before the flag is
  read. The unit test pins the flag as an argument; `main.zig` sets it where a replay reads its case.
