import os
import sys

STATE = "/tmp/unflushed-state"
path = os.path.join(STATE, "key.json")
if sys.argv[1] == "init":
    os.makedirs(STATE, exist_ok=True)
body = '{"key": "%s"}\n' % sys.argv[1]
with open(path + ".tmp", "w") as f:
    f.write(body)
    os.replace(path + ".tmp", path)  # renamed while the bytes are still in Python's buffer
