"""spike/platforms/statx-probe.py — what this kernel answers to the calls the engine's shim search
and PATH search make on Linux, with `newfstatat` beside them as the control
(RUNS-RULE-2026-10-10b.md, a probe added after the second dispatch).

    python3 spike/platforms/statx-probe.py <path>...

On Linux the engine reads a file's kind through raw `statx` (`src/posix.zig`; it has no `fstatat`
path there). The shim search asks with `AT_SYMLINK_NOFOLLOW` and the mask `TYPE|UID`
(`statNoFollow`); the `PATH` search asks `access(X_OK)` and then, following links, `TYPE`
(`isExecutableRegular`). Each is asked here in that form, by raw syscall number, so no libc
emulation stands between the question and the kernel. `access` goes through glibc, which on
x86_64 issues the `access` syscall and on aarch64, which has none, `faccessat`; both are asked
where both exist. A line reports the return value, the errno
when it is not 0, and for `statx` the mask the kernel filled.
"""

import ctypes
import errno
import os
import platform
import sys

# (statx, newfstatat, faccessat, access — None where the architecture has no such call)
NR = {"x86_64": (332, 262, 269, 21), "aarch64": (291, 79, 48, None)}
AT_FDCWD = -100
AT_SYMLINK_NOFOLLOW = 0x100
STATX_TYPE, STATX_UID = 0x1, 0x8
X_OK = 1


def main(paths):
    machine = platform.machine()
    if machine not in NR:
        print(f"statx-probe: no syscall numbers for {machine}")
        return 2
    sys_statx, sys_newfstatat, sys_faccessat, sys_access = NR[machine]
    libc = ctypes.CDLL(None, use_errno=True)
    libc.syscall.restype = ctypes.c_long
    buf = ctypes.create_string_buffer(512)
    L = ctypes.c_long

    def ask(label, nr, *args):
        ctypes.memset(buf, 0, len(buf))
        ctypes.set_errno(0)
        rc = libc.syscall(L(nr), *args)
        e = ctypes.get_errno()
        line = f"{label} = {rc}"
        if rc != 0:
            line += f" {errno.errorcode.get(e, e)}"
        elif nr == sys_statx:
            line += f" stx_mask=0x{int.from_bytes(buf.raw[0:4], 'little'):x}"
        print(line)
        return rc

    print(f"uname: {' '.join(os.uname()[2:3])} {machine}")
    control_ok = True
    for p in paths:
        b = ctypes.c_char_p(p.encode())
        ask(f"statx({p}, AT_SYMLINK_NOFOLLOW, TYPE|UID)", sys_statx,
            L(AT_FDCWD), b, L(AT_SYMLINK_NOFOLLOW), L(STATX_TYPE | STATX_UID), buf)
        if sys_access is not None:
            ask(f"access({p}, X_OK)", sys_access, b, L(X_OK))
        ask(f"faccessat({p}, X_OK)", sys_faccessat, L(AT_FDCWD), b, L(X_OK))
        ask(f"statx({p}, 0, TYPE)", sys_statx, L(AT_FDCWD), b, L(0), L(STATX_TYPE), buf)
        if ask(f"newfstatat({p}, AT_SYMLINK_NOFOLLOW)", sys_newfstatat,
               L(AT_FDCWD), b, buf, L(AT_SYMLINK_NOFOLLOW)) != 0:
            control_ok = False
    print(f"control: {'newfstatat answered every path' if control_ok else 'newfstatat failed — an apparatus fault'}")
    return 0 if control_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
