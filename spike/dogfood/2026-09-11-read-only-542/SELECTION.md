# Selection — 2026-09-11, the two targets a read-only call had refused (#542)

**Nothing was screened, and that is the whole of the selection.** This run is not a slate
chosen from candidates: it is the two targets already on record as refused for a call that
changes nothing, measured again before and after the change that reads those two calls as
reads. Both were named before the change existed:

| Target | Where it was already recorded | The call it was refused for |
|---|---|---|
| mlr 6.13.0 | `spike/followup-item4/NOTES.md` (2026-09-08), the control of that sweep | `epoll_ctl` |
| ocrmypdf 16.7.0 | `spike/dogfood/2026-09-11-past-walls/RESULTS.md`, the run that filed the shape | `faccessat2` |

So there are no rejected candidates to list. What would have belonged here instead — the
question a slate's rejections answer, "is this set chosen by taste?" — is answered by the
scan that set the change's scope: every report under `spike/` whose headline is
`unsupported_syscall_observed` was read for the name on its next line, and those two are the
only calls in the list that change nothing (the others, `sendfile` and `copy_file_range`,
are writes, and were recorded before those calls were classified). The scan is in the pull
request's same-class section and in `BUILDLOG.md` (2026-09-11, #542).

**Not chosen, and why.** Other calls that change nothing on disk — extended-attribute
reads, `inotify_add_watch`, `preadv`, `poll` — are absent from the oracle's lists and would
refuse the same way, but no real target has met one here, so none of them is in the change
and none is measured in this run. `docs/report-schema.md` says so in the same paragraph that
makes the promise.
