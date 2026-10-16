-- depends: 0001-create-notes
-- Pending: add a column and backfill it.
ALTER TABLE notes ADD COLUMN body_len INTEGER;
UPDATE notes SET body_len = length(body);
