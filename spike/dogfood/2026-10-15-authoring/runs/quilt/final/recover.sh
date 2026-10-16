#!/bin/sh
# What a user runs after a crash, before using quilt again. quilt has no crash
# recovery of its own; the one repair it names itself is `quilt upgrade`, which it
# asks for when .pc/ exists without a readable .pc/.version ("The working tree was
# created by an older version of quilt. Please run quilt upgrade") -- the state a
# kill between `mkdir .pc` and the write of .pc/.version leaves. On any other tree
# it says "nothing to do" and writes nothing.
cd "${SIDEEYE_STATE_DIR:?}" || exit 1
exec quilt upgrade
