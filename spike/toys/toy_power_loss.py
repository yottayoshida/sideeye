import ctypes
import json
import os
import sys

SYNC_FILE_RANGE_WRITE = 2


def at(d, name):
    return os.path.join(d, name)


def run(variant, d):
    if variant == "log":
        with open(at(d, "app.log"), "a") as f:
            f.write("new\n")
        os.rename(at(d, "app.log"), at(d, "app.log.1"))
        return
    name = "new.json" if variant.startswith("newname") else "key.json"
    f = open(at(d, name + ".tmp"), "w")
    f.write('{"v": 1}\n')
    f.flush()
    if variant == "sync":
        os.fsync(f.fileno())
    if variant == "range":
        libc = ctypes.CDLL(None, use_errno=True)
        libc.sync_file_range(f.fileno(), ctypes.c_longlong(0), ctypes.c_longlong(0), SYNC_FILE_RANGE_WRITE)
    f.close()
    os.replace(at(d, name + ".tmp"), at(d, name))


def read(d, name):
    p = at(d, name)
    return open(p, "rb").read() if os.path.exists(p) else None


def check(variant, d):
    if variant == "log":
        logs = [read(d, "app.log"), read(d, "app.log.1")]
        if any(t is not None and set(t.splitlines()) - {b"old", b"new"} for t in logs):
            return False
        return logs[1] is None or logs[1].endswith(b"new\n")
    for name in ("key.json", "new.json"):
        data = read(d, name)
        if data is None or (variant == "newname-lax" and name == "new.json" and data == b""):
            continue
        try:
            json.loads(data)
        except ValueError:
            return False
    return True


def main():
    variant, step, d = sys.argv[1:4]
    if step == "init":
        open(at(d, "app.log" if variant == "log" else "key.json"), "w").write("old\n" if variant == "log" else '{"v": 0}\n')
    elif step == "run":
        run(variant, d)
    elif step == "check":
        sys.exit(0 if check(variant, d) else 1)


main()
