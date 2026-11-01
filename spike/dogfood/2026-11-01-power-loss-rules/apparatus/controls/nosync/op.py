# spike/faq/2026-10-10/box/fsync/nosync.py's write: no sync of the file or the directory.
import os

with open("key.json.tmp", "w") as f:
    f.write('{"key": "rotate"}\n')
os.replace("key.json.tmp", "key.json")
