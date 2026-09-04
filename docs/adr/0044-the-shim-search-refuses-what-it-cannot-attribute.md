# 0044 — The shim search refuses what it cannot attribute

Status: Accepted (2026-09-04)

Closes #423. The search that resolves `libsideeye_shim` when `--shim` is not given now
refuses a candidate that is a symlink, or that belongs to none of {the invoking user, root,
the owner of the binary}, and names the reason. It is a mitigation on a path that has no
boundary to offer, and this record exists so that is not read as more than it is.

## Context

The shim is not an accessory. It is the thing that reports what the target did, so whoever
chooses it chooses the verdict. Until now the search chose it by existence alone: `access`
then `realpath`, both of which follow links. Anyone who could write `bin/` or `../lib` of an
installed prefix could plant a link there and hand the run a library of their own, and the
run would look ordinary. #423 measured that three ways — the shipped 1.0.0 binary installed
by Homebrew, a pre-fix build of the branch, and `sideeye mcp` — each producing a verdict
with nothing said; re-measured here against a prefix copied out of the Homebrew Cellar,
which `canonicalSelf` resolves to the same real paths.

`docs/adr/0010-mcp-adapter.md` already carried an operational precondition about
`SIDEEYE_MCP_ROOT` and the work directory being user-owned and not attacker-writable. It
said nothing about the install prefix, which is the directory this is about — so the
exposure was neither covered by the precondition nor contradicted by it. It was simply
absent.

Two things constrain any answer here. The first is that this is a **shipped** command's
resolution of its own library, so a refusal that turns away a legitimate layout is a 1.x
compatibility break. The second is that nothing the engine checks can be a boundary: what
is inspected is a pathname, and what loads the library is the child's dynamic linker,
resolving that pathname again later. The window between the two cannot be closed from
here.

## Decision

**Refuse, name the reason, and do not fall through.**

`findShimBeside` answers `found`, `absent`, or `refused`, and there are three reasons to
refuse: the candidate is a symlink, its owner is not one of the accepted set, or it could
not be classified at all. The third is the one the title is about and the one easiest to
leave out — a `statx` that did not fill its mask, an EACCES, a seccomp EPERM — and folding
it into "not there" would be the same silent shape `kindAtNoFollow`'s doc already refuses
elsewhere in this codebase. A refusal ends the search: it does not try the second candidate
and does not become "no shim was found". A search that quietly
moved on would let whoever owns `bin/` steer the run to the second candidate, and a search
that reported absence would send the operator looking for a missing file instead of a
planted one. The CLI turns a refusal into a setup error and the MCP server into a tool
error, from one shared message, so the two ends cannot drift the way #389 found them
drifting.

**The accepted owners are the invoking user, root, and the owner of the binary.** The third
is what keeps a shared prefix working: an install owned by a dedicated account — Homebrew on
Linux owns `/home/linuxbrew` this way — puts the binary and the library under that same
account, and anyone who can write it can replace the binary itself, so trusting the pair
costs nothing the binary did not already cost. A binary whose owner cannot be read narrows
the accepted set to {user, root} rather than widening it.

**Symlinks are refused at the final component only.** A `../lib` that is itself a link is
followed and the owner of what it leads to is checked. Refusing on the way would turn away
the symlink farms package managers legitimately build, and the link that mattered in the
measurement was at the candidate itself.

**`--shim` and `SIDEEYE_MCP_SHIM` are unchecked.** A caller who names the path is not
relying on the search, and they remain the documented way past a refusal.

## Alternatives considered

**Refuse symlinks only.** Smaller, and it falsifies the one sentence README.md carried
("a symlink there is followed"). Declined: the same sentence names writing `bin/` or
`../lib` as the exposure, and a real file placed by an attacker is the other half of it. A
guard with one direction silent invites exactly the "we checked that" reading this record
is trying to prevent.

**Check the ownership or mode of the candidate's *directory*.** Declined: whoever plants a
file owns it, so the file's own owner already catches them; a directory check adds a second
predicate that fails differently on shared prefixes without covering a case the first one
misses.

**Record the posture and change nothing.** The state before this: README.md and ADR 0010
describe the exposure and tell an operator to set `SIDEEYE_MCP_SHIM` or fix permissions.
Declined by the owner. A documented exposure is still an exposure, and the search can
decline the one case it can attribute without asking anything of the operator.

**Close the load-time window.** Not available. `LD_PRELOAD` and `DYLD_INSERT_LIBRARIES` take
a pathname; there is no descriptor to pass.

## Consequences

- A layout whose binary and shim have *different* owners, neither of them the invoking user
  nor root, is refused. The refusal names the uid and the two ways past it, and this is
  recorded in CHANGELOG.md as a 1.x behaviour change rather than as a fix alone.
- The guard is a mitigation. README.md's environment table says so in the same breath as
  the guard, so an operator does not read a refusal-free run as a proof of anything.
- The owner predicate is a function of three uids rather than a stat inside the search,
  because the refusing case cannot be built without `chown`: unit tests falsify the
  arithmetic, and `spike/acceptance.sh` check 2so falsifies the wiring on a host that can
  chown — with the same command before and after as its control. Without that leg an
  unfilled `statx` uid reading as 0 would pass everything while every unit test stayed
  green, which is why `posix.ownedKindNoFollow` refuses a `statx` whose `UID` mask bit is
  clear. **That mask gate has no fixture** — a filesystem answering `TYPE` and not `UID` is
  what it exists for and is not something this repository can produce — so it rests on the
  argument above rather than on a measurement.
- A candidate whose kind or owner cannot be read stops the run rather than being skipped.
  On a host where `statx` is unavailable the engine has larger problems — the snapshot walk
  uses it too — but the failure now names the shim search instead of surfacing later.
- **Not narrowed:** a candidate that is a directory or a FIFO is still accepted if its owner
  is. The search answers "which file", not "is this a loadable library"; the loader answers
  the second question, loudly, and adding a kind requirement here would put a second
  opinion about the same thing in two places.
- #469 (the child stdout capture's symlink guard riding on `minimal_env`) is the same class
  in a different subsystem and is not closed here.
