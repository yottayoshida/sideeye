import os
import sys

STATE = "/tmp/keytool-py-state"
BUGGY = False


def write_key(body):
    path = os.path.join(STATE, "key.json")
    if BUGGY:  # truncate in place, then write
        with open(path, "w") as f:
            f.write(body)
            f.flush()
            os.fsync(f.fileno())
        return
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(body)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


if sys.argv[1] == "init":
    os.makedirs(STATE, exist_ok=True)
    write_key('{"key": "one"}\n')
elif sys.argv[1] == "rotate":
    write_key('{"key": "two"}\n')
