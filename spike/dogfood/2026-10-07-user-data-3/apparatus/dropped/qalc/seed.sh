set -eu
rm -rf /s/aux/data/qalculate /s/aux/home/.config/qalculate /s/qalc-in && mkdir -p /s/qalc-in
printf 'myrate := 42\nhourly := 120\nsave definitions\n' > /s/qalc-in/seed.txt
printf 'myrate := 44\nsave definitions\n' > /s/qalc-in/op.txt
qalc -f /s/qalc-in/seed.txt > /s/qalc-in/seed.log 2>&1
grep -rq myrate /s/aux/data/qalculate
