# bs1770gain — define (explored)

Debian description: "measure and adjust audio and video sound loudness";
`implemented-in::c`, `use::converting`, `works-with::audio`. Installed
0.9.5-1 in the trixie image (FFmpeg-based). Freshness: no tracked file outside
the selection names it (`b2-author.sh`, 2026-09-18).

man bs1770gain: "loudness scanner and normalizer based on ITU-R BS.1770 …
helps normalizing the loudness of audio and video files to the same level";
`-o <folder>,--output <folder>` — "write RG tags or apply the EBU/ATSC/RG gain,
respectively, and output to folder"; `--track-tags` — "write track tags";
`--help` adds "specify either option -o/--output or option --overwrite but not
both". Measured while authoring (container, 0.9.5): with `-o` a WAV input is
remuxed to `<name>.mka` in the output folder carrying the tags (a WAV cannot
hold them); with `--overwrite` the same `.mka` appears beside the untouched
WAV — so the documented state-changing operation writes a new file either
way, and the define uses the primary `-o` form. Local-file state, documented
non-interactive writer → define. The state holds one 2-second 440 Hz mono WAV
written by `setup.sh` with python3's `wave` module (python3 is in the sweep
image) and an empty `out/` folder; the operation writes the tagged copy there.

Repeatability was the open question when this was written: a Matroska
segment carries a muxing date unless the muxer is told otherwise, and
bs1770gain exposes no such switch. `preflight --twice` is where that is
answered, and a refusal on it is the nondeterministic-writer class arriving
through the funnel — a result, not an apparatus failure (the first group's
lbdb note).

**Authoring run (2026-09-18, v1.5.0 in the trixie image):** `preflight --twice`
did not reach the repeatability question. The first observed run was refused
**`unsupported_syscall_observed` — `mkdirat`**: the oracle saw the tool create
a directory under the state and the default observation mode does not count
that call. The refusal's `next_step` sends the reader to the README's limit
list and to DESIGN.md; it does not name `--observe syscalls`, so under this
group's run contract the sweep records the first leg and runs no second —
the engine's own advice governs which leg is run, and here it gives none. The
define stands as written: nothing in it can stop the tool creating its
folder, and changing the operation to avoid the call would be the
define-budget tuning the protocol forbids. Exit 2, no `first_accepted_recording`.
