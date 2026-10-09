#!/bin/sh
# The auth store holds a bcrypt hash with a fresh salt, so two clean runs leave different bytes and the
# file is declared scratch; this checker judges it instead. alice must log in with her old password or
# her new one, and bob with his, through Home Assistant's own reader. Anything else (a file it cannot
# parse, a user gone, neither password) is a failure.
d=$SIDEEYE_STATE_DIR
v() { /opt/ha/bin/hass --script auth -c "$d" validate "$1" "$2" 2>&1 | tail -1; }
a1=$(v alice pw-three); a0=$(v alice pw-one); b=$(v bob pw-two)
case "$a1$a0" in *"Auth valid"*) ;; *) echo "alice logs in with neither password ($a1 / $a0)"; exit 1 ;; esac
case "$b" in "Auth valid") ;; *) echo "bob does not log in ($b)"; exit 1 ;; esac
exit 0
