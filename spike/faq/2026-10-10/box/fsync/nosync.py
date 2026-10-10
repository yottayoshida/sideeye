import os
import sys

STATE = "/tmp/nosync-state"
path = os.path.join(STATE, "key.json")
if sys.argv[1] == "init":
    os.makedirs(STATE, exist_ok=True)
body = '{"key": "%s"}\n' % sys.argv[1]
with open(path + ".tmp", "w") as f:  # no flush to disk, no fsync
    f.write(body)
os.replace(path + ".tmp", path)  # and no fsync of the directory either
