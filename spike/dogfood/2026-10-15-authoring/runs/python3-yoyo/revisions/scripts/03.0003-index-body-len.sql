-- depends: 0002-add-body-len
-- Pending: add an index.
CREATE INDEX idx_notes_body_len ON notes (body_len);
