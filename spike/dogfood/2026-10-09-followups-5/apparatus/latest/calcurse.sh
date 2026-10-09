# lfos/calcurse#529, the report's steps with /work for /tmp and calcurse 4.8.2.
D=/work/c/d; C=/work/c/conf
mkdir -p "$D" "$C"
printf 'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nUID:grace-001\nDTSTART:20260902T100000Z\nDTEND:20260902T110000Z\nSUMMARY:GraceStandup\nEND:VEVENT\nBEGIN:VEVENT\nUID:ada-001\nDTSTART:20260901T100000Z\nDTEND:20260901T110000Z\nSUMMARY:AdaMeeting\nEND:VEVENT\nEND:VCALENDAR\n' > /work/two.ics
/opt/calcurse/bin/calcurse -D "$D" -C "$C" -q -i /work/two.ics
cat "$D/apts"
strace -f -qq -P "$D/apts" -e trace=write -e inject=write:signal=KILL:when=1 /opt/calcurse/bin/calcurse -D "$D" -C "$C" -P --filter-pattern AdaMeeting; echo "exit $?"
wc -c "$D/apts"
