#!/bin/sh
# commitizen must still read the project's version, and it must be the old one or the new one.
cd /s/cz/repo || exit 1
v=$(cz version --project 2>&1) || { echo "cz version --project failed: $v" >&2; exit 1; }
case "$v" in 0.1.0|0.2.0) exit 0 ;; *) echo "cz reads the project version as '$v'" >&2; exit 1 ;; esac
