# Prediction — the latest releases of two targets, committed before either is run (2026-10-02)

tombi and biome have each released since the version in the 2026-09-28 box: tombi v1.7.0
(2026-10-01, the box has 1.5.6) and biome 2.5.15 (2026-09-30, the box has 2.5.14). The writer
is the same lines in both at those tags (`transcripts/receipts/after-the-fail.txt`). Each
release binary is mounted over the box's own and the same define is run again
(`apparatus/latest-host.sh`).

Predicted: both **FAIL** in the same shape — the file at 0 bytes between the cut and the write —
and both at 0 bytes under `ulimit -f 0`. Fairly sure: the source did not change.
