# The file synced before the rename, and the directory after it.
import os

with open("key.json.tmp", "w") as f:
    f.write('{"key": "rotate"}\n')
    f.flush()
    os.fsync(f.fileno())
os.replace("key.json.tmp", "key.json")
d = os.open(".", os.O_RDONLY)
os.fsync(d)
os.close(d)
