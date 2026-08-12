#!/bin/sh
# The tool's own reader as the L2 checker: if watson cannot list its frames after a
# crash and a restart, the database it left behind is not one it can use.
exec watson frames
