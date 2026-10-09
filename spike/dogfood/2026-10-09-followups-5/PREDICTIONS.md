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

## Round 2: the awaiting reports on their projects' latest releases

The recount also found twelve reports still awaiting a reply that were measured on a release older than the
project's latest — five of them older than the latest even on the day they were filed (dotenvx 2.32.4 where
2.34.1 was out; stow 2.3.1, calcurse 4.7.1, SoftHSM 2.6.1 and topydo 0.14 where 2.4.1, 4.8.2, 2.7.0 and 0.16
were). Whether each report still stands on the latest release is measurable now. Each report's own steps are
run on the latest release, as written except for paths (`apparatus/latest/<name>.sh`). WP-CLI is left out: the
2.12.0 the report measured is still its latest release.

| report | measured on | latest | prediction |
|---|---|---|---|
| Exiv2/exiv2#9482 | 0.28.5 (Debian) | 0.28.9 | still: its fix PR #9504 is unmerged |
| andreafrancia/trash-cli#414 | 0.24.5.26 | 0.26.9.29 | still: no fix was referenced |
| aspiers/stow#139 | 2.3.1 | 2.4.1 | still |
| aws/aws-cli#10648 | 2.23.6 (Debian) | 2.37.x | still: PR #10649 is unmerged |
| beancount/beancount#1051 | 3.1.0 (Debian) | 3.2.3 | still: PR #1054 is unmerged |
| dotenvx/dotenvx#1012 | 2.32.4 | 2.34.1 | still: the report read the same write on main |
| hashicorp/terraform#39299 | 1.16.4 | 1.16.5 | still |
| lfos/calcurse#529 | 4.7.1 | 4.8.2 | still |
| ocrmypdf/OCRmyPDF#1762 | 16.7.0 (Debian) | 17.13.0 | still: a contributor reproduced the mechanism on main today |
| softhsm/SoftHSMv2#908 | 2.6.1 | 2.7.0 | still |
| topydo/topydo#341 | 0.14 | 0.16 | still |
