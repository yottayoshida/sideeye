import json
import os
import sys

home = os.path.expanduser("~")
config_dir = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config"), "xdgtool")
data_dir = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share"), "xdgtool")


def write_db(n):
    with open(os.path.join(data_dir, "db.json"), "w") as f:  # truncate in place: the planted bug
        json.dump({"generation": n}, f)


if sys.argv[1] == "init":
    os.makedirs(config_dir, exist_ok=True)
    os.makedirs(data_dir, exist_ok=True)
    with open(os.path.join(config_dir, "config.json"), "w") as f:
        json.dump({"name": "demo"}, f)
    write_db(1)
elif sys.argv[1] == "bump":
    with open(os.path.join(config_dir, "config.json")) as f:
        json.load(f)
    write_db(2)
