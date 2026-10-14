# One broken state per leg of CANDIDATES.md 3.4, each breaking that leg alone where that can be
# built, on the completed state.
LEGS="a b c d"
DB=/s/dj/db.sqlite3
break_a() { sqlite3 $DB "INSERT INTO django_migrations (app, name, applied) VALUES ('app', '0003_ghost', '2026-01-01 00:00:00');"; }
break_b() { sqlite3 $DB "ALTER TABLE app_note ADD COLUMN extra TEXT;"; }
break_c() { sqlite3 $DB "DELETE FROM app_note WHERE id = 50;"; }
# Migration 1 recorded with migration 1's table, and a table already named the way migrate's
# table rebuild names its new one, so the next migrate cannot create it.
break_d() { sqlite3 $DB "CREATE TABLE app_note_old AS SELECT id, text AS body, CAST(rank AS TEXT) AS rank FROM app_note; DROP TABLE app_note; CREATE TABLE app_note (id integer NOT NULL PRIMARY KEY AUTOINCREMENT, body text NOT NULL, rank varchar(10) NOT NULL); INSERT INTO app_note SELECT * FROM app_note_old; DROP TABLE app_note_old; DELETE FROM django_migrations WHERE name = '0002_change'; CREATE TABLE new__app_note (x INTEGER);"; }
