Thank you for turning this around so quickly. I built `main` at 3501ef34 and measured it
again, and the new sequence has a failure mode the old one did not have. That is on me: I
filed the original report without saying what I thought a fix should look like, and I am
sorry — with that in it, this round would probably not have been necessary.

## What the patch does now

```
renameat("img1.png", "img1.png~")           = 0
linkat("img1.png~", "img1.png")             = 0     <- new
openat("img1.png", O_RDWR|O_CREAT|O_TRUNC)  = 3
unlinkat("img1.png~")                       = 0
```

After the `link` both names are one inode, so the `O_TRUNC` immediately after empties the
backup together with the target.

## The consequence needs no crash at all

A failing `WriteImages` is the case the code already handles: `rename(backup_filename,
image->filename)` puts the original back. With the hard link there is nothing to put back,
because the bytes under both names were truncated and partly rewritten before the failure.

On a 200 KB tmpfs, `mogrify -resize 1600%` against a 98,851-byte PNG. `mogrify` exits 1 in
both builds:

| build | `img1.png` | `img1.png~` |
| --- | --- | --- |
| 7.1.1-43 | 98,851 bytes, sha256 equal to the original, decodes | absent |
| 3501ef34 | 204,800 bytes, links=2, fails to decode | 204,800 bytes, same inode, fails to decode |

Repro, in a container with a 200 KB tmpfs at `/tiny`:

```sh
magick -size 128x128 xc: +noise Random /src.png
cp /src.png /tiny/img1.png
mogrify -resize 1600% /tiny/img1.png      # exits 1, ENOSPC
sha256sum /src.png /tiny/img1.png /tiny/img1.png~
```

## Under a crash

Killing the process at each syscall boundary: at crash point 4 of 5, after the `open` and
before the first `write`, `img1.png` and `img1.png~` are both 0 bytes with links=2. The
invariant "the original is readable under one of the two names" was true in every world
under 7.1.1-43 and is false under 3501ef34.

## The window I reported is shorter, not closed

Crash point 2 of 5, between the `rename` and the `link`, still leaves no file at
`img1.png` — the state the issue describes.

## What I would do instead

Write to a sibling temp name and rename it over the original. One `rename`, no backup:

```
write   img1.png.magick-<pid>
rename  img1.png.magick-<pid> -> img1.png
```

`rename(2)` replaces the destination atomically within a filesystem, so every crash point
leaves `img1.png` holding either the old bytes or the new ones, and a failed write leaves
the original untouched — the temp file is just removed.

Three details need care, which is why I am describing a direction rather than claiming it
works as written:

1. `WriteImages` picks the coder from the filename, so the temp path needs the coder made
   explicit — the `"%s:%s"` form already built a few lines above for `magic` does exactly
   this.
2. The temp file is a new inode, so mode and ownership have to be copied from the original
   before the rename. Worth noting that the current patch is *better* than the old code
   here: opening through the link keeps the original inode, and so keeps its mode and
   owner, which `O_CREAT` on a fresh file did not.
3. `preserve-timestamp` still needs its `set_file_timestamp` call, on the temp file before
   the rename.

If you would rather not carry that, reverting is a perfectly good outcome from where I sit.
What I reported was minor and fully recoverable; what is in `main` now is not.

## Offer

If you would like, I can open a PR along those lines, measured the same way as this comment
— the ENOSPC path and every crash point — and you can take it or leave it. I will not open
one unless you say so.

## Not claimed

Process-kill and ENOSPC paths only, on aarch64 Linux (Debian trixie), against a build of
the 3501ef34 tarball. I have not measured power loss, torn writes, other filesystems, or
the Windows `_wlink` path. The crash measurements come from
[sideeye](https://github.com/yottayoshida/sideeye), the tool named in the original report.
