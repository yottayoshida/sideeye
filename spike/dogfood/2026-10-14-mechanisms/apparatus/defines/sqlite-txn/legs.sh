# One broken state per leg of CANDIDATES.md 2.1, each breaking that leg alone, on the completed state.
LEGS="a b c"
DB=/s/sq/ledger.db
# The index's definition changed under its content: integrity_check reports rows missing from it,
# while the table the other legs read is untouched.
# Python's sqlite3, not the CLI: the CLI runs in defensive mode and refuses to write sqlite_schema.
break_a() { python3 -c "import sqlite3; c = sqlite3.connect('$DB', isolation_level=None); c.execute('PRAGMA writable_schema = ON'); c.execute(\"UPDATE sqlite_schema SET sql = 'CREATE INDEX accounts_bal ON accounts(id)' WHERE name = 'accounts_bal'\")"; }
break_b() { sqlite3 $DB "UPDATE accounts SET bal = 81 WHERE id = 'B'; REINDEX;"; }
break_c() { sqlite3 $DB "DELETE FROM journal;"; }
