# One broken state per leg of CANDIDATES.md 3.1, each breaking that leg alone, on the completed state.
LEGS="a b c"
S=/s/lr
break_a() { echo "line B1" >> $S/app.log; }
break_b() { rm -f $S/app.log; }
break_c() { printf 'logrotate state -- version 2\nthis is not a state line\n' > $S/status; }
