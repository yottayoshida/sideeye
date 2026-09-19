# Contract card — `dos2unix` (shape: atomic single-file rewrite)

Sealed before the run for this target. Every claim carries a backing (`documented`, `measured`,
`unspecified`); `unspecified` claims are excluded from grading (PROTOCOL.md, "The answer key").
Package version in the box: **7.4.3-1** (Debian bookworm).

## What the tool does

`dos2unix FILE` converts a file's line endings in place.

## Claims

| # | claim | backing | evidence |
|---|---|---|---|
| 1 | The default mode rewrites the named file itself ("old file mode"), rather than writing a second file | `documented` | `man dos2unix`: "This version does by default in-place conversion (old file mode), while the original SunOS/Solaris version only supports paired conversion (new file mode)." |
| 2 | The rewrite is **old-or-new**: the converted bytes are assembled in a temporary file and the original is replaced by `rename`, so a crash leaves either the original contents or the converted ones — never a half-converted file | `measured` | `strace -f -e trace=file,rename dos2unix f.txt` in the box: `openat(AT_FDCWD, "./d2utmpDVSrPn", O_RDWR\|O_CREAT\|O_EXCL, 0600) = 4` … `fchmodat(AT_FDCWD, "./d2utmpDVSrPn", 0100644)` … `renameat(AT_FDCWD, "./d2utmpDVSrPn", AT_FDCWD, "f.txt") = 0`. No write to the original's descriptor appears |
| 3 | The temporary lives **in the same directory as the file**, named `d2utmp` + six characters, so a crash between its creation and the rename leaves that file behind in the judged tree | `measured` | same trace: the path is `./d2utmpDVSrPn`, relative to the file's directory |
| 4 | A leftover `d2utmp*` is not part of the tool's promise: nothing reads it on the next run, and the conversion is re-runnable with the original untouched | `measured` | the trace shows the temporary is created `O_EXCL` with a fresh random name each run, and the file's own contents are read from the original descriptor; a second `dos2unix` on the same file converts it again without consulting any `d2utmp*` |
| 5 | Whether a leftover `d2utmp*` should be reported as a defect by a crash-consistency tool — garbage in the state directory versus a violated promise | `unspecified` | the manual never mentions the temporary at all, so nothing states an intent about what a crash may leave beside the file |
| 6 | Ownership and permissions of the converted file are preserved in the default mode, and a failure to preserve them aborts the conversion unless `--allow-chown` is given | `documented` | `man dos2unix`, `--allow-chown`: "Allow file ownership change in old file mode. When this option is used, the conversion will not be aborted when the user and/or group ownership of the original file can't be preserved in old file mode." |

## What a checker should assert

That the file holds either exactly the pre-operation bytes or exactly the converted bytes, with
no third state — claim 2 is the contract. A checker that accepts "the file exists" is vacuous
here, because the file always exists: the rename is atomic and the original is never truncated.

**Not** that the directory holds nothing else: claim 5 is unspecified, so a define that turns on
the leftover temporary is `unresolved by card`, not wrong. A define that declares `d2utmp*`
scratch is respecting claim 4 and is valid.
