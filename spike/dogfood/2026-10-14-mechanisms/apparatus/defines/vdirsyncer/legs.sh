# One broken state per leg of CANDIDATES.md 2.5, each breaking that leg alone, on the completed state.
LEGS="a b c"
S=/s/vd
# A recovery that succeeds always evens the two sides, so leg a can only stay broken when the
# recovery cannot run: four removed from one side and the status directory replaced by a file.
break_a() { rm -f $S/a/cal/four.ics; rm -rf $S/status; : > $S/status; }
break_b() { cp $S/b/cal/two.ics $S/b/cal/two-again.ics; }
break_c() { rm -f $S/a/cal/two.ics $S/b/cal/two.ics; rm -rf $S/status; mkdir $S/status; }
