# Dogfood runs — the index

One row per run, newest first. A row is written when the run's directory is
committed, and it names what the run cost as well as what it found: a run that
reached no verdict is a result about Sideeye, not a failed run.

| Run | Targets | Verdicts | Named walls | Reported upstream |
|---|---|---|---|---|
| [2026-09-05-userview](2026-09-05-userview/) | 8 measured, 12 screened out | **4 FAIL** — mogrify, qpdf, exiv2, rdiff-backup | **4** — chezmoi and gopass `no_shim_marker` (static Go), beets and joplin `multiple_threads_detected` | 2 filed ([Exiv2#9482](https://github.com/Exiv2/exiv2/issues/9482), [ImageMagick#8939](https://github.com/ImageMagick/ImageMagick/issues/8939)); 2 already known ([qpdf#1773](https://github.com/qpdf/qpdf/issues/1773) — this project's own, [rdiff-backup#1084](https://github.com/rdiff-backup/rdiff-backup/issues/1084) — a third party's) |

## What the first row settled beyond its own targets

- **Node/libuv is measured.** `docs/target-classes.md`'s "Not yet measured"
  section carried Node as a labelled prediction — the thread wall, seen on toys,
  never on a real Node target. joplin CLI 3.6.x meets it. The row moved.
- **Two more static-binary examples, and a sharper statement of the class.**
  #390 measured `gh` as static on Linux and dynamic via Homebrew, and concluded
  that the language does not decide the wall. chezmoi and gopass are the harder
  case: every artifact their projects publish for Linux is static (tarball *and*
  `.deb`, both measured), and neither is in Debian, so for a Linux user there is
  no build that Sideeye can enter.
- **A refusal that reads as the wrong diagnosis.** `no_shim_marker` names the
  static linkage only when the operation's first word is a path. Written the way
  a user writes it — `chezmoi apply …`, resolved through `PATH` — the same
  refusal says Sideeye did not resolve the binary, which reads as "use a full
  path" when nothing about the path is the problem.
