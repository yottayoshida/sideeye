-- The migration already applied before the operation: the table and its 100 rows.
CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 100)
INSERT INTO notes (id, body) SELECT i, 'note ' || i FROM n;
