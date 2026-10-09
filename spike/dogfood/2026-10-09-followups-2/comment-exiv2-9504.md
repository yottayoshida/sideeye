I measured this PR at 8e2fc85 on Linux against the case in #9482. The truncation is gone: a kill during the write now leaves the original picture whole. One window is left on non-Windows systems: `replaceFileAtomically` removes the original (`fs::remove(pf)`) before it renames the temporary over it, so a kill between the two leaves nothing at the original name. The new content survives beside it as `pic1.jpg.exv-tmp-<pid>-<n>`.

To reproduce (Debian 13 arm64, this PR built with `-DBUILD_SHARED_LIBS=OFF`):

```
ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 pic1.jpg
exiv2 -M"set Exif.Image.Artist probe" pic1.jpg
strace -f -qq -P "$PWD/pic1.jpg" -e trace=unlinkat,renameat,renameat2 \
  -e inject=renameat,renameat2:signal=KILL ./exiv2 rm "$PWD/pic1.jpg"
ls -l
```

strace shows `unlinkat("pic1.jpg")` succeed and the process killed at `renameat("pic1.jpg.exv-tmp-54-0", "pic1.jpg")`; afterwards only `pic1.jpg.exv-tmp-54-0` (301 bytes) is there.

On POSIX, `rename(2)` replaces an existing destination in one step, so the remove is not needed there, and dropping it from the `#else` branch would close this window. The remove-then-rename looks like it came from the Windows path, where a plain rename fails when the target exists. This is a direction, not something I have built and measured.

Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest. Not measured: power loss (neither the temporary nor the directory is fsynced, which a kill does not need), and other filesystems.
