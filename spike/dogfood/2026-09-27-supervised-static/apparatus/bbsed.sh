#!/bin/sh
# The plan's `sh -c "busybox sed -i ..."`, spelled as a script because a define given as flags
# splits on spaces with no quoting (docs/cli.md). Dynamic dash starts, then `exec`s the static
# busybox in the same process — the exec into a static image that --observe syscalls cannot
# follow (its filter stays, its handler does not).
exec /bin/busybox sed -i s/a/z/ /tmp/bb/f.txt
