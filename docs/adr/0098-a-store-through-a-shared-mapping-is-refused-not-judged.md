# 0098 — A store through a shared mapping is refused, not judged

- **Status:** Accepted (2026-10-08)
- **Refs:** #689 (from the 2026-10-05 whole-product review); ADR 0045 (the shim is silent
  about the *change* an mmap store makes, not about the file); ADR 0030 (refusals report
  observations); ADR 0053 (children judged under an oracle); `docs/contract-freeze.md`
  surface 2 (no new `unknown_reason` member).
- **Scope:** `src/oracle.zig`, `src/main.zig` (strace's filter), `src/contract.zig` (v19),
  `shim/src/ops.zig`, `shim/src/macos.zig`, `shim/src/darwin_libc.zig`,
  `shim/src/common.zig`, `spike/toys/toy.c`, `spike/acceptance.sh`, `DESIGN.md`,
  `docs/report-schema.md`, `docs/target-classes.md`.

## Context

A file mapped `MAP_SHARED` changes when the program stores into memory. No call happens
at that moment, so neither the shim, the syscall trap nor the supervising engine can place
a crash point before a store: Sideeye's worlds are the states between calls, and the
states between two stores are not among them. The whole-product review asked for a
decision — judge it, or decline it with the reason.

What it found had to be measured first, because the answer was assumed to be "refused":

- **Linux, under an oracle, by the subject:** refused. `oracle.zig` read
  `mmap(…PROT_WRITE…, MAP_SHARED, <fd in the state>)` as `unsupported_syscall_observed`.
  rrdtool, astropy's `fitscheck` and goaccess stop there (`spike/outcome-funnel.tsv`), and
  LMDB's `lock.mdb` met it in the authoring-cost study.
- **Linux, by a child:** not refused. The same line from a child was counted as the child
  touching the state, and a child whose other writes the shim recorded is admitted by the
  v15 rule (ADR 0053) — so the stores rode the run to its verdict.
- **Either platform, a mapping made writable later:** not seen. A state file mapped shared
  and read-only, then given `PROT_WRITE` by `mprotect`, is as writable as one mapped so.
  strace's filter (`%file,%desc,%process,…`) did not include `mprotect`, so the oracle never
  read the line, and the macOS shim interposed neither call.
- **macOS:** not refused. The shim did not interpose `mmap`, and fs_usage's reader files
  `mmap` and `munmap` among the read-only calls. Measured on 2026-10-08 on macOS arm64
  with `--allow-unverified`: a target that `ftruncate`s a file, stores into two pages of a
  writable shared mapping and closes it passed **3/3**, with a checker that rejects one
  page new and the other old, because no crash point fell between the stores. Without
  the `ftruncate` the zero-operations guard caught it; with any recorded mutation beside it
  that guard is silent.

## Decision

**Stores through a shared mapping are not judged. A run in which a file under the state
directory can be written through one is refused `unsupported_syscall_observed`, and the
refusal names how** — unless another refusal comes first: a child the v15 rule does not
admit is refused as that, before the oracle's account is read.

Two spellings, both observations:

- `mmap(PROT_WRITE|MAP_SHARED)` — the mapping was made writable.
- `mprotect(PROT_WRITE) on a shared mapping of a state file` — a shared mapping of a state
  file the observer saw made read-only was given `PROT_WRITE`.

Where each is issued:

- **Linux, under an oracle** (every observation mode): the oracle reads both, from the
  subject and from every child. strace now traces `mprotect`, `pkey_mprotect` and `mremap`
  as well; the oracle remembers each read-only shared mapping of a state file the run
  opened for writing — address from the return, length rounded up to the page, a split line
  joined across its `<… resumed>` half, a failed one ignored, a range `mremap` moved or
  duplicated (`old_size` 0) remembered at its new place — and refuses a `PROT_WRITE`
  `mprotect` that overlaps one and did not visibly fail, from any process, since a forked
  child shares the parent's mappings. A writable shared mapping that visibly failed is not
  refused. A file opened only read-only can never be given `PROT_WRITE` on a shared mapping,
  and is not remembered: memmap2's read-only shape, mapped and unmapped, would otherwise
  leave an address that the allocator or a JIT reuses and makes writable — a refusal that
  turns on address-space layout, and names a state file it never saw. The open and the
  mapping are matched by the name strace prints, which is the name at that call, so once the
  run has renamed or linked anything — `db.tmp` opened, renamed to `db`, then mapped — the
  match is given up and every state file mapped shared is remembered, refusing more rather
  than less.
- **macOS, with or without an oracle:** the shim interposes `mmap` and `mprotect`
  (contract v19). An anonymous or private mapping passes straight through. A writable
  shared mapping of a state file is refused in scope, as `exchangedata` is. A read-only one
  is remembered when its descriptor was opened for writing — the kernel refuses
  `PROT_WRITE` on a shared mapping of a descriptor opened read-only (`EACCES`), so nothing
  else can become writable — in a table of 32 slots; past them, every later `PROT_WRITE`
  `mprotect` is refused, under its own message (`… after more shared mappings of state
  files than the shim tracks`), since which range it touched can no longer be told. A
  mapping that failed is not refused.
- **Linux without an oracle** is unchanged: such a run already reaches PASS only under
  `--allow-unverified`, and its report says nothing checked the shim's account.

The stores themselves are what is declined. A read-only shared mapping is not refused:
bbolt maps its file that way and writes through `pwrite`, and those writes are calls like
any other (`spike/dogfood/2026-09-27-supervised-static/transcripts/chezmoi/entry-oracle.txt`
is the shape).

## Alternatives considered

**Crash points at `msync` and `munmap`.** They add worlds at those calls, but a world can
still only be a state between calls: a store and the next store have no call between
them, and a PASS would claim the states between them were explored when none was built.
Rejected as a partial answer that reads as a whole one.

**Write-protect the pages and take the first store's fault.** The only way to stop a
process *at* a store. It gives page-sized worlds — a second store to the same page is
invisible until the page is protected again, which needs single-stepping — and from inside
the process it means handling `SIGSEGV`/`SIGBUS`, which Go and the JVM own. From outside,
Linux's userfaultfd write-protection could do it for the supervising engine only, as a new
observation mechanism. The reach is the four walls above. Declined on cost; this is the
decision to revisit if shared-mapping stores become a common wall.

**Refuse every shared mapping of a state file whose descriptor can write.** Needs neither
`mprotect` nor a table, and covers the later-writable case outright. It refuses bbolt's
shape, which is judged today and writes through calls. Rejected.

**Track `munmap` too.** Lets a range be forgotten when unmapped. A remembered range that
was unmapped can only add a refusal — a later `PROT_WRITE` `mprotect` landing on an address
reused for something else — never hide a store, and tracing `munmap` costs a line per
`free` of a large block in every target. Not taken.

**Detect in the Linux shim as well.** The oracle sees raw calls and children, in every
mode including supervised, where no shim is loaded. A shim-side copy would answer only what
the oracle already answers, and v12 left Linux's `unsupported` refusals to the oracle.

## Consequences

- Contract v19. A v18 shim under a v19 engine refuses `contract_version_mismatch`, and a
  case saved under v18 replays `case_no_longer_applies` (`docs/report-schema.md`).
- strace writes more lines for a target that changes page protections often — a JIT. The
  oracle reads `mprotect` only against remembered ranges, so a run with no shared mapping of
  a state file is judged as before; what grows is the capture and the line count the report
  prints.
- What stays unseen: on macOS, the Mach calls that map or protect memory without passing
  through `mmap` or `mprotect` — `vm_protect`, `mach_vm_protect`, `vm_remap`,
  `mach_vm_remap`, a `mach_vm_map` of a memory entry — and a program that imports the
  syscall stubs `__mmap` or `__mprotect` by name (`spike/check-macos-coverage.py` lists
  them); on both platforms, a file mapped writable outside the state and renamed into it;
  and on Linux without an oracle, all of it. A writable shared mapping through a descriptor
  the macOS shim cannot place is not among them: it refuses as `unresolvable_path`, as
  every such descriptor does.
- On macOS this newly refuses what Linux's oracle already refused: an SQLite database in
  WAL mode, whose `-shm` file is mapped writable, and LMDB, whose `lock.mdb` is, when
  either is under the state directory. Declaring the file `scratch` does not lift it — the
  refusal is about what the engine can observe, not about what the verdict judges.
- The refusal's step stays `class_wall`: nothing in a define makes a shared-mapping store
  observable.
