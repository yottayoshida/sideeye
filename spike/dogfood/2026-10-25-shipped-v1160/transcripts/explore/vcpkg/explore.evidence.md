## What happened

`/s/vcpkg/vcpkg remove zlib` was interrupted between two of its own file operations. This is crash point 9 of 54 that Sideeye explored; it is the earliest one whose result differed.

## Consequence

| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |
|---|---|---|---|---|---|---|
| `arm64-linux/debug/lib/libz.a` | file, 356910 bytes | absent | file, 356910 bytes | yes | no | no |
| `arm64-linux/debug/lib/pkgconfig/zlib.pc` | file, 305 bytes | absent | file, 305 bytes | yes | no | no |
| `arm64-linux/include/zconf.h` | file, 17006 bytes | absent | file, 17006 bytes | yes | no | no |
| `arm64-linux/include/zlib.h` | file, 103848 bytes | absent | file, 103848 bytes | yes | no | no |
| `arm64-linux/lib/libz.a` | file, 148022 bytes | absent | file, 148022 bytes | yes | no | no |
| `arm64-linux/lib/pkgconfig/zlib.pc` | file, 302 bytes | absent | file, 302 bytes | yes | no | no |
| `arm64-linux/share/doc` | directory | absent | directory | yes | unknown | no |
| `arm64-linux/share/doc/zlib` | directory | absent | directory | yes | unknown | no |
| `arm64-linux/share/doc/zlib/zlib` | directory | absent | directory | yes | unknown | no |
| `arm64-linux/share/doc/zlib/zlib/LICENSE` | file, 1002 bytes | absent | file, 1002 bytes | yes | yes (at `arm64-linux/share/zlib/copyright`) | no |
| `arm64-linux/share/doc/zlib/zlib/algorithm.txt` | file, 9345 bytes | absent | file, 9345 bytes | yes | no | no |
| `arm64-linux/share/doc/zlib/zlib/crc-doc.1.0.pdf` | file, 776142 bytes | absent | file, 776142 bytes | yes | no | no |
| `arm64-linux/share/doc/zlib/zlib/rfc1950.txt` | file, 20502 bytes | absent | file, 20502 bytes | yes | no | no |
| `arm64-linux/share/doc/zlib/zlib/rfc1951.txt` | file, 36944 bytes | absent | file, 36944 bytes | yes | no | no |
| `arm64-linux/share/doc/zlib/zlib/rfc1952.txt` | file, 25037 bytes | absent | file, 25037 bytes | yes | no | no |
| `arm64-linux/share/doc/zlib/zlib/txtvsbin.txt` | file, 5193 bytes | absent | file, 5193 bytes | yes | no | no |
| `arm64-linux/share/man` | directory | absent | directory | yes | unknown | no |
| `arm64-linux/share/man/man3` | directory | absent | directory | yes | unknown | no |
| `arm64-linux/share/man/man3/zlib.3` | file, 4482 bytes | absent | file, 4482 bytes | yes | no | no |
| `arm64-linux/share/zlib` | directory | absent | directory | yes | unknown | no |
| `arm64-linux/share/zlib/ZLIB-static-debug.cmake` | file, 843 bytes | absent | file, 843 bytes | yes | no | no |
| `arm64-linux/share/zlib/ZLIB-static-release.cmake` | file, 841 bytes | absent | file, 841 bytes | yes | no | no |
| `arm64-linux/share/zlib/ZLIB-static.cmake` | file, 4132 bytes | absent | file, 4132 bytes | yes | no | no |
| `arm64-linux/share/zlib/ZLIBConfig.cmake` | file, 1591 bytes | absent | file, 1591 bytes | yes | no | no |
| `arm64-linux/share/zlib/ZLIBConfigVersion.cmake` | file, 1861 bytes | absent | file, 1861 bytes | yes | no | no |
| `arm64-linux/share/zlib/copyright` | file, 1002 bytes | absent | file, 1002 bytes | yes | yes (at `arm64-linux/share/doc/zlib/zlib/LICENSE`) | no |
| `arm64-linux/share/zlib/usage` | file, 200 bytes | absent | file, 200 bytes | yes | no | no |
| `arm64-linux/share/zlib/vcpkg-cmake-wrapper.cmake` | file, 401 bytes | absent | file, 401 bytes | yes | no | no |
| `arm64-linux/share/zlib/vcpkg-spdx-resources.json` | file, 489 bytes | absent | file, 489 bytes | yes | no | no |
| `arm64-linux/share/zlib/vcpkg.spdx.json` | file, 17087 bytes | absent | file, 17087 bytes | yes | no | no |
| `arm64-linux/share/zlib/vcpkg_abi_info.txt` | file, 1421 bytes | absent | file, 1421 bytes | yes | no | no |
| `vcpkg/info/zlib_1.3.2_arm64-linux.list` | file, 1322 bytes | absent | file, 1322 bytes | yes | no | no |
| `vcpkg/status` | file, 1313 bytes | file, 1315 bytes | file, 1313 bytes | yes | no | no |
| `vcpkg/updates/0000000000` | absent | absent | file, 266 bytes | no | — | no |

`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.

## Where it was interrupted

```
after:  rename
        /s/vcpkg/installed/vcpkg/updates/incomplete
<-- the process was terminated here -->
before: unlink
        /s/vcpkg/installed/arm64-linux/debug/lib/libz.a
```

The operation named under `after` completed; the one under `before` never ran.

## Built-in invariant

the checker (L2) — (named by the checker, not by path): the checker exited non-zero after restart

## Checker

The define's own checker rejected the state in this world.

Its last output line, up to its first 400 bytes:

> checker(vcpkg): zlib.h is still on disk after the re-run

## Reproducing it

```
sideeye replay /out/vcpkg/work-explore/cases/000001.json --oracle /usr/bin/strace
```

Saved case: `/out/vcpkg/work-explore/cases/000001.json`

With `--leave-crash-state` added, a replay whose report says `crash_state_left: true` ends with the state directory holding what that replay's kill left, before the checker ran.

## Recovery

Not configured — this run did not measure whether the tool repairs the state on its next start.

## What this measurement did and did not establish

- The run carried no observation caveats.

Measured by Sideeye 1.16.0 (trace contract v19) against `/s/vcpkg/installed`.
