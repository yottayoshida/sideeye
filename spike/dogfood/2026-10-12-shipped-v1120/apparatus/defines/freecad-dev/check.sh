#!/bin/sh
# After a crash the part document opens and its box is either the old length or the new.
exec /opt/freecad-dev/usr/bin/freecadcmd /s/fcaux/check.py < /dev/null
