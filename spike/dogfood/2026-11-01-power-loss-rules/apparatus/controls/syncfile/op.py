# The file synced before the rename; the directory not synced after it.
import os

with open("key.json.tmp", "w") as f:
    f.write('{"key": "rotate"}\n')
    f.flush()
    os.fsync(f.fileno())
os.replace("key.json.tmp", "key.json")
