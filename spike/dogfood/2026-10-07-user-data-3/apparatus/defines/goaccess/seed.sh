set -eu
rm -rf /s/goa /s/goa-in && mkdir -p /s/goa/db /s/goa-in
i=0; while [ $i -lt 30 ]; do echo "10.0.0.$((i%7)) - - [07/Oct/2026:10:$((10+i%50)):00 +0000] \"GET /page$((i%5)) HTTP/1.1\" 200 $((100+i)) \"-\" \"curl/8\""; i=$((i+1)); done > /s/goa-in/a.log
i=0; while [ $i -lt 20 ]; do echo "10.0.1.$((i%3)) - - [07/Oct/2026:11:$((10+i%50)):00 +0000] \"GET /other$((i%4)) HTTP/1.1\" 404 $((50+i)) \"-\" \"curl/8\""; i=$((i+1)); done > /s/goa-in/b.log
goaccess /s/goa-in/a.log --log-format=COMBINED --persist --db-path=/s/goa/db -o /s/goa-in/a.html > /s/goa-in/seed.log 2>&1
test "$(ls /s/goa/db | wc -l)" -gt 100
