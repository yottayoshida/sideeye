#!/bin/sh
# After a crash the books still hold every transaction as the user entered it: nine journals of two
# legs each; each journal sums to zero, or, for the two the seed broke, to what it was broken to (the
# repair not reached yet); Checking and Savings keep their balances; the rent goes to the employer's
# account or to the expense account the repair made for it. The running balance columns are derived
# and not read. With `strict` (the recovery's check), every journal sums to zero and the rent goes to
# an expense account: the repair is done.
exec python3 - "$SIDEEYE_STATE_DIR/database.sqlite" "${1:-}" <<'PY'
import sqlite3, sys
strict = sys.argv[2] == "strict"
try:
    # Opened for writing, as Firefly opens it: a crash inside a transaction leaves a hot journal that
    # SQLite rolls back on this open, and a read-only open refuses ("attempt to write a readonly database").
    db = sqlite3.connect(sys.argv[1])
    ic = db.execute("pragma integrity_check").fetchone()[0]
    js = db.execute("select j.id, j.description, count(t.id), round(sum(t.amount), 2) from transaction_journals j left join transactions t on t.transaction_journal_id = j.id and t.deleted_at is null where j.deleted_at is null group by j.id").fetchall()
    bal = dict(db.execute("select a.name, round(sum(t.amount), 2) from transactions t join accounts a on a.id = t.account_id where a.name in ('Checking', 'Savings') and t.deleted_at is null group by a.name").fetchall())
    rent = db.execute("select a.name, at.type from transactions t join transaction_journals j on j.id = t.transaction_journal_id join accounts a on a.id = t.account_id join account_types at on at.id = a.account_type_id where j.description = 'Rent' and t.amount > 0").fetchall()
except Exception as e:
    print(f"checker(firefly): the database does not read: {e}"); sys.exit(1)
bad = []
if ic != "ok": bad.append(f"integrity {ic}")
if len(js) != 9: bad.append(f"{len(js)} journals")
for jid, desc, n, s in js:
    if n != 2: bad.append(f"journal {jid} has {n} legs")
    if s != 0 and (strict or (jid, s) not in ((4, -2.1), (5, -1.75))): bad.append(f"journal {jid} ({desc}) sums to {s}")
if bal != {"Checking": 3052.7, "Savings": 8500.0}: bad.append(f"balances {bal}")
if len(rent) != 1 or rent[0][0] != "Employer" or (strict and rent[0][1] != "Expense account"): bad.append(f"rent goes to {rent}")
print(f"checker(firefly{' strict' if strict else ''}): {len(js)} journals; balances {bal}; rent to {rent}; " + ("ok" if not bad else "; ".join(bad)))
sys.exit(1 if bad else 0)
PY
