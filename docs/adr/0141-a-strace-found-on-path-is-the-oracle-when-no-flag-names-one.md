# 0141 — On Linux, a strace found on PATH is the oracle when no flag says otherwise, once it has traced this binary

- **Status:** Accepted (2026-10-31)
- **Refs:** #950; #78 (named, not attached — the decision this reverses); `README.md` Usage; `docs/cli.md`;
  `docs/contract-freeze.md` surface 3.
- **Scope:** `src/cli.zig` (the decision and the probe), `src/refuse.zig`, `src/report.zig`, `src/mcp.zig`, `sideeye demo`.

## Context

A PASS needs a second witness or `--allow-unverified`. Since #78 the engine has looked for a strace on `PATH`
and, when it found one, named it in the completeness refusal without using it: a witness joining on its own
would strengthen what a flagless verdict claims and move every caller that had measured the flagless
behaviour. The cost of that choice is the first run a new user makes: a define explored without flags ends
UNKNOWN `completeness_not_verified` even on a machine that has the witness, the refusal says to pass
`--oracle`, and the README's quick start showed `--allow-unverified` beside it — the unwitnessed path was the
short one. The 2026-10-18 product review named that entry cost (#950).

The owner ruled on 2026-10-31 that no flag may mean "witness if one is found", and that a flag must exist to
say "no witness".

## Decision

1. **When.** On Linux, when none of `--oracle`, `--oracle-fs-usage`, `--no-oracle` and `--allow-unverified`
   is given, a strace found on `PATH` (an absolute directory, executable by this user) is the oracle of
   `explore`, `preflight` and `replay`. `--allow-unverified` alone attaches nothing: it is the caller's explicit
   statement that no witness is wanted, and an unverified PASS (exit 0) made with it stays exit 0. macOS is
   unchanged: its witness needs `sudo` and cannot be taken without being asked for.
2. **Found once, before the setup.** `PATH` is searched while the arguments are read, before any command of the
   define runs, and not again: a setup can write into a directory on `PATH`, and a strace it put there would be
   the witness of its own run. Once it has been tried and attached, the report says the witness was found (the
   `oracle` sentence says so, and names its path once the comparison completes; `oracle_witness` is
   `"strace"` as for `--oracle`). A run stopped before the try reports no oracle, as a flagless run did.
3. **Tried before it is trusted.** Before the recording run, the found strace traces this binary's `version`
   with the trace classes the recording run asks for, under a ten-second budget. If it cannot — ptrace denied, a
   strace too old for the classes, anything that does not exit 0 — it is not attached, and the run continues as
   a run without an oracle: `completeness_not_verified` for a would-be PASS, with the strace's first complaint in
   the message. The try happens before anything is recorded, so a refusal the oracle raises later is never
   mistaken for "could not attach". A strace that passes the try and then fails in the recording run fails as
   one named with `--oracle` would.
4. **`--no-oracle`** attaches none and is exclusive with `--oracle` and `--oracle-fs-usage`. The completeness
   refusal says it was given instead of naming a strace.
5. **Callers that keep the old meaning.** `sideeye mcp` passes `--no-oracle` to its children unless
   `SIDEEYE_MCP_ORACLE` names a witness — the operator's variable stays the server's only way to choose one
   (surface 5 does not move). `sideeye demo` passes `--no-oracle`: its FAIL needs no witness.

## Alternatives considered

- **`--oracle` with no path searches `PATH`.** No flag would keep its meaning, and the first run would still be
  the unwitnessed one; it does not meet #950. Declined by the owner.
- **Refuse (SETUP ERROR) when the found strace cannot trace.** A CI that denies ptrace would move from exit 2 to
  exit 3 on every run, for a witness it never asked for.
- **Attach under `--allow-unverified` too.** Its unverified PASS would become a comparison that can refuse, moving
  exit 0 to exit 2 for a caller that said in as many words that it accepts the weaker claim.
- **Trust only a root-owned strace.** Nix and Linuxbrew install strace owned by the user; the directories on a
  user's `PATH` are already theirs to trust. Decision 2 keeps a setup from putting a strace of its own
  ahead on `PATH`; a setup that can overwrite the file found there could replace the witness, as it
  could the file `--oracle` names, and that is not guarded against.

## Consequences

- Which runs reach which exit code moves for runs given no oracle flag on a Linux host with a strace that can
  trace (surface 3's dated note): a would-be PASS that was UNKNOWN (exit 2) is verified and exits 0, or refuses
  under the oracle; a run refused `boundary_without_oracle` (exit 2) can reach a verdict; and a FAIL (exit 1) can
  become an UNKNOWN when the oracle's account disagrees with the recording's — the disagreement is the oracle
  doing its job, not a regression. The verdict-to-code mapping is unchanged and no reason is added.
- A run with a found witness runs strace: slower, and on a host whose ptrace is allowed but whose strace
  misbehaves on the target, refused where it used to be judged without one. `--no-oracle` is the way back.
- The printed lines name only the oracle a flag named. A strace found on `PATH` is left off the replay line and
  the preflight's next line, since a flagless run on Linux finds it again and the path would ride to macOS or into
  an evidence bundle; the next line ends `--no-oracle --allow-unverified` when `--no-oracle` was given, and in a
  `--oracle <strace>` blank when no strace, or one that could not trace, was found.
