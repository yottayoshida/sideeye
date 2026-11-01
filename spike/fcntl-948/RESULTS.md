# `fcntl(F_FULLFSYNC)` counted as `fsync` on macOS (#948)

Measured 2026-10-31 on macOS 15.3.1 (24D70), Apple silicon, Zig 0.17.0, cargo and go from Homebrew.

## How libsystem_kernel's `fcntl` reads its third argument

`dyld_info -disassemble /usr/lib/system/libsystem_kernel.dylib`, the `_fcntl` symbol (arm64e slice):

```
_fcntl:
  sub   sp, sp, #0x20
  stp   x29, x30, [sp, #0x10]
  add   x29, sp, #0x10
  add   x8, x29, #0x10        ; va_list: the caller's first stack slot
  str   x8, [sp, #0x8]
  sub   w8, w1, #0x2a         ; cmd - 42
  cmp   w8, #0x47
  b.hi  0x1e30
  ...                         ; jump table over cmd 42..113
  ldr   x8, [sp, #0x8]        ; pointer commands:
  add   x9, x8, #0x8
  str   x9, [sp, #0x8]
  ldr   x2, [x8]              ;   one slot, read as 64 bits
  bl    ___fcntl
  ...
  sub   w8, w1, #0x7          ; cmd 7..10 are pointer commands too
  cmp   w8, #0x4
  b.lo  0x1e10
  ldr   x8, [sp, #0x8]        ; every other command:
  add   x9, x8, #0x8
  str   x9, [sp, #0x8]
  ldrsw x2, [x8]              ;   one slot, read as a sign-extended int
  b     0x1e20
```

Every path reads exactly one variadic slot, whatever the command, and narrows it there. So the
shim's wrapper reads the slot whole and passes it on unchanged; the real function narrows it.

`dyld_info -exports` lists `_fcntl`, `_fcntl$NOCANCEL`, `___fcntl` and `___fcntl_nocancel`;
`dyld_info -imports /usr/lib/system/libsystem_c.dylib` imports `___fcntl`,
`___fcntl_nocancel` and `_fcntl$NOCANCEL`. A sync libc issued on its own behalf would go through
those, not through the interposed name; which libc functions issue one was not looked for.

## The wrapper passes each command the caller's argument

`spike/toys/toy_fcntl.c`, run plain and with `DYLD_INSERT_LIBRARIES` naming the shim: the
outputs are identical (`F_GETFL`, `F_SETFL`, `F_GETPATH`, `F_SETLK`, `F_GETLK`, `F_DUPFD`,
`F_SETFD`/`F_GETFD`, `F_FULLFSYNC`, `F_BARRIERFSYNC`, `F_NOCACHE`, a bad descriptor and a bad
command). Against a wrapper that read the argument as an `int`, four lines differed:

```
< getpath rc=0 errno=-
< getpath base=plain.dat
< setlk rc=0 errno=-
< getlk rc=0 errno=-
< getlk type=unlck
---
> getpath rc=-1 errno=Bad address
> getpath base=(none)
> setlk rc=-1 errno=Bad address
> getlk rc=-1 errno=Bad address
> getlk type=wrlck
```

CI's macOS job runs the same comparison.

## Before and after, without a witness

The FAQ's toys (`spike/faq/2026-10-10/box/rs` and `box/go`), clean and with the planted bug,
`sideeye explore --allow-unverified`, the engine and shim built from `origin/main` (`651ad406`,
contract v19) and from this change (contract v20):

| build | toy | verdict | crash points |
|---|---|---|---|
| main | Rust, clean | PASS | 3 |
| main | Rust, bug | FAIL | 2 |
| main | Go, clean | PASS | 3 |
| main | Go, bug | FAIL | 2 |
| this | Rust, clean | PASS | 4 |
| this | Rust, bug | FAIL | 3 |
| this | Go, clean | PASS | 4 |
| this | Go, bug | FAIL | 3 |

The recorded trace of the Rust bug build reads `open`, `write`, `fsync`, `close` on `key.json`,
and the Go clean build's `open`, `write`, `fsync`, `close`, `rename` on `key.json.tmp`
(`trace-ops`). The Rust bug build's three crash points are the three its Linux run explores
(`spike/faq/2026-10-10/RESULTS.md`).

## Not measured here

`--oracle-fs-usage` needs root, and this machine's sudo asks for a password. The same toys run
under it in check 15 of `spike/fsusage/acceptance-local.sh`, on CI's macOS runner.
