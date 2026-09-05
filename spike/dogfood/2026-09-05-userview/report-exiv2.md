## What happens

`exiv2 rm` (and any operation that writes metadata back through the generic transfer path) replaces the image by truncating the original file in place. From `src/basicio.cpp`, `FileIo::transfer`:

```cpp
if (auto fileIo = dynamic_cast<FileIo*>(&src)) {
    ...
    fs::rename(fileIo->path(), pf);      // temp-file source: replaced by rename
} else {
    // Generic handling, reopen both to reset to start
    if (open("w+b") != 0) {              // <- truncates the original
      throw Error(ErrorCode::kerFileOpenFailed, path(), "w+b", strError());
    }
    if (src.open() != 0) { ... }
    write(src);                          // <- the new bytes arrive only here
    src.close();
}
```

JPEG metadata writing reaches the `else` branch, because `JpegBase::writeMetadata` builds the result in a `MemIo` rather than a temporary `FileIo`. A crash after `open("w+b")` and before `write(src)` completes leaves **a zero-byte file where the image was**. There is no temporary file and no backup, so the original bytes are gone.

The `if` branch of the same function already does the safe thing — build elsewhere, then `rename` — which is why this reads as a gap rather than a design decision.

## Measured

exiv2 0.28.5 (Debian package `0.28.5+dfsg-1`), Debian GNU/Linux 13 (trixie), aarch64.

The write path, under `strace`, for a single file:

```
openat(AT_FDCWD, "/work/f/ex/one.jpg", O_RDONLY) = 3     (x4, reading)
openat(AT_FDCWD, "/work/f/ex/one.jpg", O_RDWR|O_CREAT|O_TRUNC, 0666) = 3
```

No temporary file, no backup, no rename.

Crashing the process deterministically at each syscall boundary of `exiv2 rm pic1.jpg pic2.jpg pic3.jpg` and examining the directory afterwards. Crash point 2 of 6 — after the truncating `open` of `pic1.jpg`, before the write:

Before:

```
pic1.jpg   319 bytes   (identify reads it)
pic2.jpg   319 bytes
pic3.jpg   319 bytes
```

After a crash at that point:

```
pic1.jpg     0 bytes   <- identify cannot read it; the original bytes are not anywhere
pic2.jpg   319 bytes   <- untouched
pic3.jpg   319 bytes   <- untouched
```

3 of 7 explored worlds (6 crash points + the baseline) left an unreadable image. A second witness (`strace`) agreed with the recorded operations.

The current `main` carries the same `FileIo::transfer` shown above, so this is not something 0.28.5 alone does.

## Why this one may be worth more than the usual in-place-write report

The truncate-then-write shape is common and is usually a minor matter: the same window exists in code formatters, and there the file being rewritten is under version control, so the loss is a `git checkout`. Photographs are not usually under version control. A user who loses power while stripping metadata from a directory of images has no copy to restore from, and `exiv2` is often run over originals rather than over exports.

Two possible responses, and I have no stake in which:

1. Route the generic branch through a temporary file in the same directory and `rename` it into place — the `if` branch above already does exactly this, so the pieces exist.
2. If that is not wanted, a line in the documentation saying that an interrupted write leaves the file truncated would at least let a user decide whether to work on a copy.

## Disclosure

Found with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I write and maintain. It runs the operation once, records the syscalls it makes inside a declared directory, then re-runs it killing the process before each one and checks an invariant over the result. I have no commercial interest in it — it is a personal open-source project — and I name it so you can see exactly how the claim was produced and reproduce it yourself. If you would rather not have tool-generated reports on this tracker, say so and I will stop.

The invariant here was "each file named on the command line is readable by `identify`". It was falsified against deliberately corrupted state before the run, so a checker that could not fail was not used to produce this.

## Not claimed

I have not measured what happens under power loss or a torn write; this is process-kill granularity only, so it says what happens when the process dies between two syscalls and nothing about what the filesystem does with partially-flushed data. Concurrent processes are also outside what was measured.
