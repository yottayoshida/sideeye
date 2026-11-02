# Known silent windows

The README promises that a target Sideeye cannot fully observe is UNKNOWN, never a silent PASS,
except for the windows on this page. A **window** is a known way a run **under an oracle**
(`--oracle`, `--oracle-fs-usage`, or `--observe syscalls` or `supervised` with one) reaches
**PASS** while an operation or a change to the state went unseen. Three things are not windows,
and are not listed:

- a gap that ends in a refusal: that run is UNKNOWN, which is the promise kept;
- a run under `--allow-unverified`: its report already says the claim is the weaker one;
- a FAIL judged on an account with something missing: the promise is about PASS.

Each window says what shows it — a report field that counts it, or a test that pins its
behaviour so a change to it is noticed — or that nothing does, and where it was decided. CI holds
this page to the gaps the ADRs record (ADR 0145).

| Window | What happens | What shows it | Where |
|---|---|---|---|
| `rename-in-from-outside` | A directory a recorded `rename` moved into the judged tree from outside is attributed to that one record, because its source was never snapshotted, so a later unrecorded write inside that subtree can still reach PASS. | `paths_attributed_to_rename` in the JSON report, and the text report's `atomicity` line when it is not zero; the test `reconcile: a renamed-in directory carries its children, and the count says so` (`src/engine/snapshot.zig`) | [DESIGN.md](../DESIGN.md#a-directory-renamed-in-from-outside), ADR 0032 |
| `explored-worlds-no-oracle` | Under `--oracle-fs-usage` (macOS) explored worlds run without an oracle, so a process that behaves differently in a world than in the recording — writes the recording did not, or leaves the process group there — is judged on what the shim records in that world. Under `--oracle` every explored world runs under strace (ADR 0149). | Nothing in the report; under `--oracle`, `oracle_worlds` counts the worlds strace was compared in | ADR 0149, ADR 0002, ADR 0053, ADR 0065 |
| `child-ops-one-witness` | When a run's writing children are crash points, the oracle compares the subject's operations only; a child's write that neither witness places is left to the per-path reconciliation of the snapshots. | `oracle_verified_subject_only` true | ADR 0053 |
| `reconciliation-per-path-gap` | A write neither witness records, or records without a place in the state, is caught only where no record that could have put those bytes there names the file. Known ways to make one: io_uring; an `ioctl` the oracle does not refuse (`BTRFS_IOC_ENCODED_WRITE`, `XFS_IOC_EXCHANGE_RANGE`, `FS_IOC_ZERO_RANGE`, `FS_IOC_UNRESVSP`; it refuses only the clones, `FICLONE` and `FICLONERANGE`); on macOS, a line `fs_usage` drops where the shim also missed the call, a neighbouring process writing through a descriptor it opened before the capture began, a relative write after a thread that recorded nothing moved the working directory, or a child the shim is not loaded into leaving the process group. | Nothing in the report; the rule is pinned by the test `reconcile: a file left holding bytes is accounted for only by a record that can have put them there (#814)` (`src/engine/snapshot.zig`) | [DESIGN.md](../DESIGN.md), "Some calls put bytes in a file"; ADR 0121, ADR 0031, ADR 0060 |
| `shared-mapping-store-unseen` | A store through a shared writable mapping that was not refused: on macOS one made through the Mach VM calls or the `__mmap` and `__mprotect` stubs, and on either platform a file mapped writable outside the state and then renamed into it. A store has no call behind it. | Nothing in the report. | ADR 0098 |
| `scratch-unrecorded-write` | A path the define declares `scratch` is accounted for by any operation that names it, so an unrecorded write to it is not explored, and a checker can still read it. | `l0`'s count of the paths matched by `scratch`, which are not judged | [docs/report-schema.md](report-schema.md) |
| `failed-dir-rename-replayed` | A directory rename that failed for a reason the names do not show (permissions, a sticky directory) is replayed as having moved its subtree, so unrecorded calls that rebuild the names end on the snapshot's names. Under an oracle it needs a write neither witness records, so it arises only together with the windows above. | Nothing in the report. | ADR 0137 |
| `sigsys-loss-child-death` | Under `--observe syscalls`, a child that lost `SIGSYS` (a raw `rt_sigaction`, glibc's `posix_spawn` child) dies at its first trapped call; a target that survives that death is judged without the child's work. | Nothing in the report; [docs/report-schema.md](report-schema.md) item (4) names the ways `SIGSYS` is lost | ADR 0063 |

The last three are listed on the safe side: whether `scratch-unrecorded-write` is a window or the
define's own choice, and whether `failed-dir-rename-replayed` and `sigsys-loss-child-death` reach
PASS at all, was read from the design rather than measured.
