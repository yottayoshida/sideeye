# 2026-09-06 — re-measuring the fix ImageMagick wrote for #8939

The 2026-09-05 run reported [ImageMagick/ImageMagick#8939](https://github.com/ImageMagick/ImageMagick/issues/8939):
an interrupted in-place `mogrify` leaves no file at the original name, with the
content at `<file>~`. It was written as minor, with an explicit invitation to
close it, because the original survived intact and a rename restored it.

A maintainer reproduced it and merged a patch the same day
([1a0d1b71](https://github.com/ImageMagick/ImageMagick/commit/1a0d1b71), then
[3501ef34](https://github.com/ImageMagick/ImageMagick/commit/3501ef34) walking
back one line of it). This run measures that patch.

**It narrows the window that was reported and opens a wider one that was not:
under the patch the original can be lost outright, and reaching that does not
require a crash.**

## The patch arrived in two commits

`1a0d1b71` (2026-09-05T18:38:12Z) added the `link` call and, on the success path,
added `remove_utf8(image->filename)` alongside the existing
`remove_utf8(backup_filename)`. `3501ef34` (23:49:21Z, five hours and eleven
minutes later) removes that one line and changes nothing else. The maintainer's
comment on the issue is timestamped 18:39:03Z — 51 seconds after the first
commit, so it announces a patch rather than a reviewed one.

What that added line would have done under the `link` is a reading of the diff,
not a measurement: this run builds 3501ef34 only and makes no claim about how
1a0d1b71 behaves.

## What changed in the write path

`apparatus/record-syscalls.sh`, output in `transcripts/syscalls.txt`:

```
                                                          7.1.1-43   3501ef34
renameat("img1.png", "img1.png~")                            yes        yes
linkat("img1.png~", "img1.png")                               -         yes
openat("img1.png", O_RDWR|O_CREAT|O_TRUNC)                   yes        yes
unlinkat("img1.png~")                                        yes        yes
```

The `link` gives the original name a second directory entry for the *same
inode*. That closes most of the reported window — the name is occupied again a
few microseconds after the rename. The `O_TRUNC` on the next line then empties
that inode, and with it the backup.

## Three measurements

Both builds in one container: Debian's `imagemagick` 7.1.1-43 Q16 aarch64
(`8:7.1.1.43+dfsg1-1+deb13u11`) at `/usr/bin/mogrify`, and a build of the
3501ef34 tarball (reporting itself as 7.1.2-32 Beta Q16-HDRI) at
`/opt/im/bin/mogrify`. aarch64 Linux, Debian trixie, Sideeye v1.2.0 (trace
contract v13), oracle `strace`.

### 1. The same checker, before and after the patch

Two invariants, each run against both builds — `apparatus/run-explore.sh`,
transcripts in `transcripts/`:

- **`check-original-name.sh`** — the file named on the command line exists and
  `identify` reads it. This is what #8939 reported.
- **`check-recoverable.sh`** — *either* `img1.png` or `img1.png~` holds an image
  `identify` can read. This is what makes the reported behaviour recoverable.

| run | verdict | L0 (built-in atomicity) | the written checker |
|---|---|---|---|
| 7.1.1-43 × original-name | FAIL 2/5 | cp2 `rename` → `open` | cp2, same point |
| 7.1.1-43 × recoverable | FAIL 2/5 | cp2 `rename` → `open` | **never false, in any world** |
| 3501ef34 × original-name | FAIL 2/6 | cp2 `rename` → `link` | cp2, same point |
| 3501ef34 × recoverable | FAIL 2/6 | cp2 `rename` → `link` | **cp4 `open` → `write`** — "holding neither the old nor the new content" |

All four verdicts are FAIL, and reading only the verdict column would say the
patch changed nothing. The rows that matter are the last column. Under
7.1.1-43 the recoverable invariant is true in every world: the name is empty for
an instant, and the bytes are always somewhere. Under 3501ef34 there is a world
where they are nowhere — `img1.png` and `img1.png~` are both 0 bytes with
`links=2`, one truncated inode under two names.

The patch also does not close the window it was written for: crash point 2 of 5,
between the `rename` and the `link`, still leaves no file at `img1.png`.

### 2. The same loss without any crash

`WriteImages` failing is a case the code already handles:
`rename(backup_filename, image->filename)` puts the original back. With the hard
link there is nothing to put back — both names were truncated and partly
rewritten before the failure.

`apparatus/fail-path.sh` on a 200 KB tmpfs, `mogrify -resize 1600%` against a
98,852-byte PNG. `mogrify` exits 1 under both builds
(`transcripts/enospc.txt`):

| build | `img1.png` | `img1.png~` |
|---|---|---|
| 7.1.1-43 | 98,852 bytes, `links=1`, sha256 equal to the original, decodes | absent |
| 3501ef34 | 204,800 bytes, `links=2`, sha256 differs, decode fails part way | 204,800 bytes, same inode, same sha256, same failure |

This is the finding that does not need Sideeye to reproduce: four shell lines
and a small tmpfs. It is also the more serious one, because a full disk is not
a rare event and no process has to die.

The image is generated with `+noise Random`, so its size moves by a byte or two
between runs; the run quoted in the upstream comment measured 98,851 bytes.

### 3. What the patch does better than the old code

Worth recording because a fix should not undo it: 7.1.1-43 renames the original
aside and creates a *fresh* inode with `O_CREAT`, so the written file carries new
mode and ownership. Opening through the link keeps the original inode, and with
it the original mode and owner. Any replacement — including the temp-file
direction below — has to copy those across explicitly.

## Novelty

Not applicable in the usual sense: this is not a new finding about a tool, it is
a measurement of a patch written in response to this project's own report, four
hours after it was filed. Nothing was searched for prior art because the code
under test is one day old.

## What went upstream

A comment on the existing issue rather than a new one, written on the
measurements above:
[#8939 (comment)](https://github.com/ImageMagick/ImageMagick/issues/8939#issuecomment-5555825615).
It carries the syscall difference, the ENOSPC table, the two crash points, a fix
direction — write to a sibling temp name and `rename` it over the original, with
the three details that need care — and an offer to open a PR, conditional on the
maintainer asking for one.

A copy of what was posted is in `upstream-comment.md`.

That reply is a second round, not a first report, and its form belongs in
`spike/upstream-report-template.md` rather than here.
