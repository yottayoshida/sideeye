**Up front: this is minor, and closing it as won't-fix is a perfectly good outcome.** No data is lost — the original survives under a `~` suffix, which is exactly what the code intends — and the recovery is a rename. I am reporting it because I measured it rather than guessed it, and because the leftover file is easy to miss. If you decide the current behaviour is the right trade, please just close this; no argument from me.

## What happens

`mogrify` writes in place by renaming the original aside first (`MagickWand/mogrify.c`):

```c
/* Rename image file as backup. */
(void) CopyMagickString(backup_filename,image->filename,MagickPathExtent);
for (j=0; j < 6; j++)
{
  (void) ConcatenateMagickString(backup_filename,"~",MagickPathExtent);
  if (IsPathAccessible(backup_filename) == MagickFalse)
    break;
}
if ((IsPathAccessible(backup_filename) != MagickFalse) ||
    (rename_utf8(image->filename,backup_filename) != 0))
  *backup_filename='\0';

/* Write transmogrified image to disk. */
status&=WriteImages(image_info,image,image->filename,exception);
if (status != MagickFalse)
  { ... if (*backup_filename != '\0') (void) remove_utf8(backup_filename); }
else
  { if (*backup_filename != '\0') (void) rename_utf8(backup_filename,image->filename); }
```

The design already handles failure: on a bad write the backup is renamed back. What it cannot handle is the process not surviving to reach either branch. A crash after `rename_utf8(image->filename, backup_filename)` and before the write completes leaves **no file at the original name**, with the original content sitting at `<file>~`.

## Measured

ImageMagick 7.1.1-43 Q16 aarch64 22550 (Debian package `8:7.1.1.43+dfsg1-1+deb13u11`), Debian GNU/Linux 13 (trixie), aarch64.

The write path, under `strace`, for a single file:

```
openat(AT_FDCWD, "/work/f/im/one.png", O_RDONLY) = 3     (x3, reading)
renameat(AT_FDCWD, "/work/f/im/one.png", AT_FDCWD, "/work/f/im/one.png~") = 0
openat(AT_FDCWD, "/work/f/im/one.png", O_RDWR|O_CREAT|O_TRUNC, 0666) = 3
unlinkat(AT_FDCWD, "/work/f/im/one.png~", 0) = 0
```

Crashing the process deterministically at each syscall boundary of `mogrify -resize 50% img1.png img2.png img3.png` and examining the directory afterwards. Crash point 2 of 12 — after the rename of `img1.png`, before the reopen:

Before:

```
img1.png   425 bytes
img2.png   425 bytes
img3.png   425 bytes
```

After a crash at that point:

```
img1.png~  425 bytes   <- the original, intact: identify reads it as 128x128
img2.png   425 bytes
img3.png   425 bytes
                          img1.png: absent
```

`identify img1.png~` succeeds and reports the original dimensions, so **the content survives** and `mv img1.png~ img1.png` restores the starting state exactly. 6 of 13 explored worlds (12 crash points + the baseline) had no file at one of the three names. A second witness (`strace`) agreed with the recorded operations.

The current `main` carries the same block shown above.

## Why it might still be worth a line of documentation

The window is small and the backup is the right thing to have kept — the recovery is complete and trivial — but only for someone who knows to look. A user whose machine lost power during `mogrify *.png` sees a file missing and a `.png~` they may read as an editor's leftover and delete. The `mogrify` documentation says the original file is overwritten; it does not mention the `~` file or that it can be left behind.

A sentence in the `mogrify` documentation — if the command is interrupted, the original is at `<file>~` — would cover it. Reordering the rename and the write is a real change to a well-tested path and I would not suggest it for a window this small.

## Disclosure

Found with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I write and maintain. It runs the operation once, records the syscalls it makes inside a declared directory, then re-runs it killing the process before each one and checks an invariant over the result. I have no commercial interest in it — it is a personal open-source project — and I name it so you can see exactly how the claim was produced and reproduce it yourself. If you would rather not have tool-generated reports on this tracker, say so and I will stop.

The invariant here was "each file named on the command line exists and is readable by `identify`". It was falsified against deliberately corrupted state before the run, so a checker that could not fail was not used to produce this.

## Not claimed

I have not measured what happens under power loss or a torn write; this is process-kill granularity only, so it says what happens when the process dies between two syscalls and nothing about what the filesystem does with partially-flushed data. Concurrent processes are also outside what was measured. The `-resize` argument is incidental — any in-place `mogrify` invocation reaches the same rename.
