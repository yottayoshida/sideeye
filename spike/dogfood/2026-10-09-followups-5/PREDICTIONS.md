# Predictions — 2026-10-09 follow-ups 5

Written before the runs. The fifth "おわり？": a recount of every filing against its tracker found
tombi-toml/tombi#2265 closed by the maintainer's PR #2266 (merged 2026-10-02 as `55b8549e53`, which is the
whole of v1.7.1's difference from v1.7.0) and never re-measured. The fix drops the `set_len(0)` before the
write: it seeks to 0, writes the formatted text over the old, flushes, and only then calls
`set_len(formatted length)`. That closes the empty-file window, and leaves one: when the formatted text is
shorter than the file, a kill after the write and before `set_len` leaves the new text followed by the old
file's tail. 2026-10-02's seed grows when formatted (36 → 37 bytes, `transcripts/lab-1.txt`), so it cannot
reach that window; a padded seed shrinks (108 → 37 bytes). Both releases, both seeds, the page's path
(tombi is static: the next step is `--observe supervised`).

| define | prediction |
|---|---|
| tombi 1.7.0, the growing seed | **FAIL**, as 2026-10-02: `a.toml` cut to 0 bytes and the kill before the write |
| tombi 1.7.0, the shrinking seed | **FAIL**, the same window |
| tombi 1.7.3, the growing seed | **PASS**: the one write covers the whole old file, and `set_len` changes nothing |
| tombi 1.7.3, the shrinking seed | **FAIL**: the new 37 bytes followed by 71 of the old, between the write and `set_len`. A risk to the prediction: tokio may run the write and `set_len` on two blocking-pool threads, and the run refuses `multiple_threads_detected` |
