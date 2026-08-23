# r1's refusal, kept as the reason r2 exists

`sideeye explore` against the r1 define, exit 2:

    UNKNOWN  unsupported_syscall_observed
             copy_file_range

Not a FAIL, so nothing about the define is frozen by it, and not a
property of the target: the seccomp profile r1 declared was doing exactly
what the probe measured it doing. Both accelerated primitives returned
ENOSYS and the copy fell back to the libc read/write loop with 307 bytes
landing correctly. What refused the run is that the oracle's predicate
reads a syscall's NAME and never its return value, so a call that failed
is still a call that was observed.

The revision that answers it is `../../himalaya-r2/`, whose define
surface is this one byte for byte and whose apparatus removes the
syscall instead of making it fail.

This directory is the primary evidence for that reasoning, which is why
it is committed rather than discarded. It carries no verdict about
himalaya.
