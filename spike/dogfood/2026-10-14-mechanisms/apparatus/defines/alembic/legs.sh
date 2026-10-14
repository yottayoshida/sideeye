# One broken state per leg of CANDIDATES.md 3.3, each breaking that leg alone where that can be
# built, on the completed state.
LEGS="a b c d"
DB=/s/al/app.db
break_a() { sqlite3 $DB "INSERT INTO alembic_version VALUES ('r1');"; }
break_b() { sqlite3 $DB "ALTER TABLE notes ADD COLUMN extra TEXT;"; }
break_c() { sqlite3 $DB "DELETE FROM notes WHERE id = 50;"; }
# Revision 1 recorded with revision 1's table, and the batch migration's own temporary table left
# behind, so the next upgrade cannot create it.
break_d() { sqlite3 $DB "ALTER TABLE notes DROP COLUMN created; ALTER TABLE notes RENAME COLUMN text TO body; UPDATE alembic_version SET version_num = 'r1'; CREATE TABLE _alembic_tmp_notes (x INTEGER);"; }
