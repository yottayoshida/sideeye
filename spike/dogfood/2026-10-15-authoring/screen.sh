#!/bin/sh
# screen.sh: in CANDIDATES.md's order, per shape, builds each candidate's box and runs its
# fixture and then its operation once, with no network; the first whose operation exits 0 is the
# shape's target. Writes screen.tsv. No define, checker or sideeye run is part of it: those are
# the subject's work and the measurement.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out="$here/screen.tsv"
tmp=$(mktemp -d "$HOME/.cctmp/screen-XXXXXX")
printf 'shape\trank\tpackage\tfixture_rc\toperation_rc\tnote\n' > "$out"
: > "$out.done"

fixture() {
    case "$1" in
    quilt) echo 'mkdir t && cd t && printf "a\n" > a.txt && printf "b\n" > b.txt && mkdir patches &&
        printf "%s\n" "--- t.orig/a.txt" "+++ t/a.txt" "@@ -1 +1 @@" "-a" "+A" > patches/p1.diff &&
        printf "%s\n" "--- t.orig/b.txt" "+++ t/b.txt" "@@ -1 +1 @@" "-b" "+B" > patches/p2.diff &&
        printf "p1.diff\np2.diff\n" > patches/series' ;;
    rcs) echo 'mkdir t && cd t && printf "v1\n" > notes.txt && ci -q -i -l -t-notes -mr1 notes.txt && printf "v2\n" >> notes.txt' ;;
    etckeeper) echo 'mkdir conf && printf "x\n" > conf/f && etckeeper init -d "$PWD/conf" && printf "y\n" >> conf/f' ;;
    aptly) echo 'mkdir -p p/DEBIAN && printf "Package: p\nVersion: 1\nArchitecture: all\nMaintainer: x <x@x>\nDescription: x\n" > p/DEBIAN/control &&
        dpkg-deb -b p p.deb > /dev/null && printf "{\"rootDir\": \"%s/aptly\"}\n" "$PWD" > aptly.conf && aptly -config=aptly.conf repo create local > /dev/null' ;;
    gdbmtool) echo 'printf "store k1 v1\nstore k2 v2\nstore k3 v3\n" | gdbmtool -n db.gdbm > /dev/null' ;;
    stgit) echo 'mkdir t && cd t && git init -q && git config user.email s@s && git config user.name s && printf "0\n" > f && git add f && git commit -qm base &&
        stg init && stg new p1 -m p1 && printf "1\n" >> f && stg refresh && stg new p2 -m p2 && printf "2\n" >> f' ;;
    xapian-omega) echo 'mkdir docs && printf "alpha\n" > docs/a.txt && omindex --db db --url / docs > /dev/null && printf "beta\n" > docs/b.txt' ;;
    python3-yoyo) echo 'mkdir m && printf "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);\nINSERT INTO t (v) VALUES (\"a\"), (\"b\");\n" > m/0001.sql &&
        python3 -m yoyo apply --batch --database sqlite:///app.db m > /dev/null &&
        printf "ALTER TABLE t ADD COLUMN w TEXT;\nUPDATE t SET w = v || v;\n" > m/0002.sql &&
        printf "CREATE INDEX t_w ON t (w);\n" > m/0003.sql' ;;
    xapian-tools) echo 'echo "no indexer in this box: xapian-tools alone cannot build a source database"; exit 1' ;;
    slapd) echo 'echo "not prepared: no fixture was written for slapadd"; exit 1' ;;
    python3-flask-migrate) echo 'echo "not prepared: no fixture was written for a Flask application"; exit 1' ;;
    esac
}

operation() {
    case "$1" in
    quilt) echo 'cd t && quilt push -a' ;;
    rcs) echo 'cd t && ci -q -l -mr2 notes.txt' ;;
    etckeeper) echo 'etckeeper commit -d "$PWD/conf" r2' ;;
    aptly) echo 'aptly -config=aptly.conf repo add local p.deb' ;;
    gdbmtool) echo 'printf "store k4 v4\nstore k5 v5\nstore k6 v6\n" | gdbmtool db.gdbm' ;;
    stgit) echo 'cd t && stg refresh' ;;
    xapian-omega) echo 'omindex --db db --url / docs' ;;
    python3-yoyo) echo 'python3 -m yoyo apply --batch --database sqlite:///app.db m' ;;
    *) echo 'exit 1' ;;
    esac
}

while IFS='	' read -r shape rank pkg; do
    case "$shape" in ''|'#'*) continue ;; esac
    grep -q "^$shape	" "$out.done" 2>/dev/null && continue
    name=${pkg%%=*}
    img=$(sh "$here/apparatus/build.sh" "$pkg" 2>"$tmp/build.log" | tail -1)
    if [ -z "$img" ]; then
        printf '%s\t%s\t%s\t-\t-\tthe box did not build\n' "$shape" "$rank" "$pkg" >> "$out"; continue
    fi
    docker run --rm --network=none "$img" sh -c "cd /tmp && ( $(fixture "$name") ) > /tmp/f.log 2>&1; f=\$?; echo fixture=\$f; [ \$f = 0 ] || { tail -3 /tmp/f.log; exit 0; }; ( $(operation "$name") ) > /tmp/o.log 2>&1; echo operation=\$?; tail -3 /tmp/o.log" > "$tmp/run.log" 2>&1
    f=$(sed -n 's/^fixture=//p' "$tmp/run.log"); o=$(sed -n 's/^operation=//p' "$tmp/run.log")
    note=$(grep -v -E '^(fixture|operation)=' "$tmp/run.log" | tr '\t\n' '  ' | cut -c1-200)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$shape" "$rank" "$pkg" "${f:--}" "${o:--}" "$note" >> "$out"
    [ "$f" = 0 ] && [ "$o" = 0 ] && printf '%s\t%s\n' "$shape" "$pkg" >> "$out.done"
done <<'LIST'
1	1	quilt=0.68-1
1	2	rcs=5.10.1-2
1	3	etckeeper=1.18.22-2
1	4	aptly=1.6.1+ds1-3
2	1	gdbmtool=1.24-2
2	2	stgit=0.19-2
2	3	xapian-omega=1.4.29-1
3	1	python3-yoyo=9.0.0+dfsg1-3
3	2	xapian-tools=1.4.29-3+deb13u1
3	3	slapd=2.6.10+dfsg-1
3	4	python3-flask-migrate=4.1.0-1
LIST
cat "$out.done"
