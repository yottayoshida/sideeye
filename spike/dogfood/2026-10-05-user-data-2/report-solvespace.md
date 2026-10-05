Title: A failed save empties the sketch and still reports success

A full disk during save leaves the `.slvs` file at 0 bytes, SolveSpace reports the save as successful, and in the GUI that success then deletes the `.slvs~` autosave.

### System information

- **SolveSpace version:** 3.2 (the `v3.2` tag built from source, `solvespace-cli`); `SaveToFile` in `src/file.cpp` and `GetFilenameAndSave` in `src/solvespace.cpp` are the same lines on `master` at 581f4cb
- **Operating system:** Debian 13 (trixie), aarch64

### Expected behavior

When the sketch cannot be written, the save fails and the previous file is left as it was.

### Actual behavior

`SaveToFile` opens the target with `OpenFile(filename, "wb")`, writes it with `fprintf`, ignores the result of `fclose(fh)` and returns `true`. `strace` of `solvespace-cli regenerate part.slvs`:

```
openat(AT_FDCWD, "/s/ss/part.slvs", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 3
write(3, "\261\262\263SolveSpaceREVa\n\n\nGroup.h.v=00"..., 4096) = 4096
...                     (4096-byte writes, 60,746 bytes in all)
```

With writes made to fail (`ulimit -f 0`, `SIGXFSZ` ignored, standing in for a full disk), on your `test/group/translate_asy/normal_v22.slvs` (60,318 bytes): it prints `Written '/s/ss/part.slvs'.`, exits 0, and the file is 0 bytes. Killing the process right after that `openat` leaves the same 0 bytes (replayed twice).

In the GUI, `GetFilenameAndSave` calls `RemoveAutosave()` when `SaveToFile` returns true, so after such a save the autosave would be deleted too.

### Additional information

A sketch is the design itself, so nothing regenerates it. Two directions, and I have no stake in which: check `ferror`/`fclose` and return false (the autosave survives and the user is told); or also write to a temporary file in the same directory and rename it over the sketch (may not be worth it).

Found with [Sideeye](https://github.com/yottayoshida/sideeye), which kills a command at each file operation and checks every file is either its old or its new content. It is a personal open-source project with no commercial interest; if you would rather not have tool-assisted reports here, say so and I will stop.

Not claimed: power loss, torn writes, Windows and macOS. The GUI path was read in the source, not run.
