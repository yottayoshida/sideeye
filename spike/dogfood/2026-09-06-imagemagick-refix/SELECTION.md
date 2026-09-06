# 2026-09-06 — selection

**There was no selection.** The target was fixed before the run began: the one
tool whose maintainer had merged a patch in response to this project's report.
No candidate table exists, no target was rejected, and the ordering rule this
directory added on 2026-09-05 — measure linkage and threads before writing the
candidate table — has nothing to order.

This page exists to say that rather than to leave the reader to infer it.
`spike/cohort4/SCOUT-BRIEF.md`'s reason for requiring visible rejections is that
"a slate with no visible rejections is indistinguishable from a slate chosen by
taste". A slate of one, named by an upstream commit rather than by us, is not
that failure — but it is also not a slate, and calling this file `SELECTION.md`
without saying so would read as if targets had been weighed.

What replaced selection: 3501ef34 was on `main` because of
[#8939](https://github.com/ImageMagick/ImageMagick/issues/8939), and a patch
written against a report of ours is the one case where re-measuring needs no
justification beyond the patch existing.

Rules 1–17 are not applied here. Two of them would fail on their face — the
target is not novel to this project, and the finding is not discovered blind —
and that is correct: this run is not evidence for criterion 1 and does not claim
to be. Nothing here is sealed.
