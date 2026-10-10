#!/bin/sh
# The invariant: the config is readable and the database parses, read where the tool reads them.
python3 -c '
import json, os, sys
json.load(open(os.path.join(os.environ["XDG_CONFIG_HOME"], "xdgtool", "config.json")))
json.load(open(os.path.join(os.environ["XDG_DATA_HOME"], "xdgtool", "db.json")))
'
