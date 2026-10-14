# One broken state per leg of CANDIDATES.md 3.2, each breaking that leg alone, on the completed state.
LEGS="a b c"
DB=/s/su/data.db
# An index whose definition is changed under its content: integrity_check reports it, the table is
# untouched. Python's sqlite3, not the CLI: the CLI runs in defensive mode.
break_a() { python3 -c "import sqlite3; c = sqlite3.connect('$DB', isolation_level=None); c.execute('CREATE INDEX items_qty ON items(qty)'); c.execute('PRAGMA writable_schema = ON'); c.execute(\"UPDATE sqlite_schema SET sql = 'CREATE INDEX items_qty ON items(id)' WHERE name = 'items_qty'\")"; }
break_b() { sqlite3 $DB "ALTER TABLE items ADD COLUMN extra TEXT;"; }
break_c() { sqlite3 $DB "DELETE FROM items WHERE id = 100;"; }
