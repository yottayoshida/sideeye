# 2026-09-06 — the third patch for ImageMagick#8939, measured

[`2026-09-06-imagemagick-refix`](../2026-09-06-imagemagick-refix/) measured the
patch ImageMagick wrote for #8939 and found that it lost the original outright,
with no crash required. That was reported on the issue. The maintainer reverted
it the same hour and wrote a third patch. This run measures the third one.

**It closes the window the original report described, and it removes the loss the
second patch introduced. It also breaks `preserve-timestamp`, which neither the
unpatched build nor the second patch did.**

## What happened between the two measurements

| UTC | what |
| --- | --- |
| 2026-09-05T23:49 | `3501ef34` — the second patch, the one the previous run measured |
| 2026-09-06T00:35 | the comment reporting what that run found |
| 2026-09-06T00:58 | `cd537985` — "revert" |
| 2026-09-06T01:53 | comment: "We were not confident in our original patch and have settled on a new approach. We'll push a patch tomorrow after we review and test." |
| 2026-09-06T02:16 | `72b82a8e` — the third patch |
| 2026-09-06T02:37 | `6ace9633` — "append random hex code to backup filename" |
| 2026-09-06T02:58 | `960adadd` — "match destructor to constructor" |

The three commits land 23 minutes after the comment saying they would land
tomorrow after review and test. This run measures `960adadd`, `main` as of
2026-09-06T03:40Z.

## Builds

Both in one container: Debian's `imagemagick` 7.1.1-43 Q16 aarch64 at
`/usr/bin/mogrify`, and a build of the `960adadd` tarball at
`/opt/im/bin/mogrify`. aarch64 Linux, Debian trixie, Sideeye v1.2.0 (trace
contract v13), oracle `strace`.

The tarball's build reports itself as `7.1.2-32 (Beta) Q16-HDRI aarch64
72c71e0d3:20260905` — a GitHub tarball carries no git metadata, so the version
string names an earlier commit and cannot be used to tell which patch is in the
binary. Two things were checked instead: `/src/MagickWand/mogrify.c` in the
image contains `GetRandomKey` and the `"%s~%02x%02x%02x%02x"` format and no
`link_utf8` call, and the binary's own syscalls show the temp name and the
rename. `transcripts/syscalls.txt`.

## What changed in the write path

`apparatus/record-syscalls.sh`, output in `transcripts/syscalls.txt`. The
original's mtime is set to 2020-01-01 before the run and
`-define preserve-timestamp=true` is passed, so the `utimensat` appears in the
same column as the writes.

```
                                                     7.1.1-43     960adadd
renameat("img1.png" -> "img1.png~")                    yes           -
openat("img1.png", O_RDWR|O_CREAT|O_TRUNC)             yes           -
openat("img1.png~<8 hex>", O_RDWR|O_CREAT|O_TRUNC)      -           yes
utimensat("img1.png", [.., 2020-01-01])                yes          yes
renameat("img1.png~<8 hex>" -> "img1.png")              -           yes
unlinkat("img1.png~")                                  yes           -

mtime afterwards                                   2020-01-01   2026-09-06
```

The new sequence writes to a sibling temp name and renames it over the original.
The temp name is the original plus `~` and four random bytes in hex, retried up
to 100 times until the name is free.

## What the patch fixes

### 1. The window the report described is closed

`apparatus/run-explore.sh`, transcripts `deb-*.txt` / `main-*.txt` and the
matching `.json`. Two checkers, each against both builds:

| checker | 7.1.1-43 | 960adadd |
| --- | --- | --- |
| `check-original-name.sh` — a readable file exists at the name on the command line | **FAIL**, 2 of 5 worlds | **PASS**, 4 of 4 |
| `check-recoverable.sh` — a readable image exists at the original name or at a `~` name | **FAIL**, 2 of 5 worlds | **PASS**, 4 of 4 |

Under 7.1.1-43 both fail at the same place, which is the state the issue
describes:

```
earliest    crash point 2 of 4
            after  rename(/work/im/img1.png)
            before open(/work/im/img1.png)
observed    present before and after the operation, but gone from the crashed state
```

Under `960adadd` the original name is never vacated, so every crash point leaves
it holding the old bytes. The explored world count drops from 5 to 4 because the
new sequence has one syscall fewer in the judged state.

### 2. A failed write no longer destroys the original

`apparatus/fail-path.sh`, a 200 KB tmpfs, `mogrify -resize 1600%` against a
98,852-byte PNG. Both builds exit 1. `transcripts/enospc.txt`:

| build | `img1.png` | files left in the directory |
| --- | --- | --- |
| 7.1.1-43 | 98,852 bytes, sha256 equal to the original, decodes | 1 |
| 960adadd | 98,852 bytes, sha256 equal to the original, decodes | 1 |

The second patch left both names at 204,800 bytes and neither decoding. The
third leaves the original untouched and removes the temp file, which is what the
unpatched build did.

## What the patch breaks

### `preserve-timestamp` no longer preserves anything

`www/defines/index.html` in the same tree documents
`preserve-timestamp=true|false` as "Preserve file timestamp (mogrify only)".
`apparatus/props.sh` section E and `transcripts/timestamp-strace.txt`, with the
original's mtime set to 2020-01-01:

| build | mtime after `mogrify -define preserve-timestamp=true -resize 50%` |
| --- | --- |
| 7.1.1-43 | 2020-01-01 00:00:00 |
| 960adadd | the time of the run |

The syscall order says why. `set_file_timestamp` is called on the success path
before the rename, and it is called on `image->filename` — the file the rename is
about to replace:

```
openat("img1.png~c1b4130b", O_RDWR|O_CREAT|O_TRUNC)      write the new image
utimensat("img1.png", [.., 2020-01-01])                  stamp the old file
renameat("img1.png~c1b4130b" -> "img1.png")              discard it
```

Measured on both an absolute and a relative path argument, and the result is the
same: `transcripts/timestamp-strace.txt`.

## What the patch does not change

Four things that look like regressions when the patched build is measured alone,
and are not, because the unpatched build does them too. `apparatus/props.sh`,
`transcripts/props.txt`:

| | 7.1.1-43 | 960adadd |
| --- | --- | --- |
| C — format written, given a temp name whose extension is `png~<hex>` | PNG 32x32 | PNG 32x32 |
| D — mode of an original at 0600 | 644, new inode | 644, new inode |
| J — a hard-linked second name | not updated, links drops to 1 | same |
| K — a symlink passed on the command line | replaced by a regular file, target untouched | same |

D, J and K follow from replacing the file rather than truncating it, and 7.1.1-43
already replaces it: it renames the original to `img1.png~` and creates a fresh
inode at the original name. The write-to-temp-then-rename form inherits that
behaviour rather than introducing it.

C is worth naming because it was the first thing the fix direction warned about.
`WriteImages` picks a coder from the filename, and `img1.png~c1b4130b` has no
extension a coder claims — but the clone carries `magick` from the image it was
cloned from, and the output is PNG in both builds.

Two more, `transcripts/extra.txt`: a two-frame GIF keeps both frames in both
builds, and a `PNG:` prefix on the command-line path works in both.

## Not claimed

- Process-kill and ENOSPC paths only, on aarch64 Linux (Debian trixie), against
  a build of the `960adadd` tarball. No power loss, no torn writes, no other
  filesystem, no concurrent writers, and nothing about the Windows path.
- The `rename` on the success path sets `status=MagickFalse` when it fails, and
  the `remove` of the temp file is in the branch that failure does not reach.
  Whether that leaves a temp file behind is a reading of the diff, not a
  measurement — no run here made that `rename` fail.
- Same for `CloneImageList` returning NULL: the code writes nothing and then
  renames a file it did not create. Not measured.
- The run reached no conclusion about `mogrify` paths other than the in-place
  one; `-format` and `-path` take a different branch and were not exercised.

## Reported

Nothing. The owner's call on 2026-09-06 was to stop replying on the issue and
leave a reaction instead: the two things this project reported are both fixed,
and the remaining item is a timestamp option, which is not what the report was
about. The measurement is here so that a later run — or a later beta that still
carries it — has something to compare against.
