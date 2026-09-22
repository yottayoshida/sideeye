# The write goes past libc (a raw syscall through ctypes), so the shim records the open and
# not the write, and the oracle sees both: the leg whose refusal names --observe syscalls.
import ctypes, os, platform, sys
SYS_write = {"aarch64": 64, "x86_64": 1}[platform.machine()]
fd = os.open(sys.argv[1] + "/raw.txt", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
buf = b"raw bytes\n"
ctypes.CDLL(None, use_errno=True).syscall(SYS_write, fd, buf, len(buf))
os.close(fd)
