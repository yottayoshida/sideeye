set -eu
rm -rf /s/doit && mkdir -p /s/doit/state && cd /s/doit
cat > dodo.py <<'PY'
def task_a():
    return {'actions': [lambda: True], 'file_dep': ['a.txt']}
def task_b():
    return {'actions': [lambda: True], 'file_dep': ['b.txt']}
def task_c():
    return {'actions': [lambda: True], 'file_dep': ['c.txt']}
PY
echo a > a.txt; echo b > b.txt; echo c > c.txt
doit run --backend json --db-file /s/doit/state/d.json > /s/doit/seed.log 2>&1
grep -q '"a"' /s/doit/state/d.json
