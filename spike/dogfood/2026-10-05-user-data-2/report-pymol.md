Title: `save` of a session truncates the existing .pse before writing it, so a failed write leaves it empty

## Describe the bug

When `save` writes a `.pse` over an existing session and the write fails (a full disk), the session file is left at 0 bytes, and with `-c` PyMOL still exits 0. `save` in `modules/pymol/exporting.py` (unchanged on `master` at 5e8bfca) does

```python
with fopen(filename, 'wb') as handle:
    handle.write(contents)
```

so the old session is truncated before the new one is written, and nothing else holds a copy.

## To Reproduce

1. Make a session: `fragment ala`, `fragment gly`, `save model.pse` (6,078 bytes).
2. `edit.pml`: `set bg_rgb, white`, `color red, ala`, `save model.pse`.
3. Make writes fail, standing in for a full disk: `ulimit -f 0`.
4. `python3 -m pymol -cq model.pse edit.pml`

```
Traceback (most recent call last):
  File "/usr/lib/python3/dist-packages/pymol/exporting.py", line 923, in save
    handle.write(contents)
OSError: [Errno 27] File too large
```

Exit status 0; `model.pse` is now 0 bytes.

The same happens with no disk problem if the process is killed between the open and the write. `strace` of step 4 without the limit:

```
openat(AT_FDCWD, "/s/pm/model.pse", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666) = 4
write(4, "}q\0(X\v\0\0\0moviescenesq\1]q\2(]q\3]q\4"..., 6118) = 6118
```

Killed after the `openat`, the file is 0 bytes (replayed twice).

## Expected behavior

A failed save leaves the previous session as it was.

## Environment

- **PyMOL Version:** 3.1.0
- **PyMOL Source:** apt-get pymol (Debian 13 trixie, 3.1.0+dfsg-1)
- **Operating System:** Linux aarch64

## Additional context

A session holds the scenes, views, selections and colouring, which the structure files do not, so a lost session is lost work. Two directions, and I have no stake in which: write to a temporary file in the same directory and `os.replace` it over the session; or keep the previous file as a backup before overwriting it (may not be worth it).

Found with [Sideeye](https://github.com/yottayoshida/sideeye), which kills a command at each file operation and checks every file is either its old or its new content. It is a personal open-source project with no commercial interest; if you would rather not have tool-assisted reports here, say so and I will stop.

Not claimed: power loss, torn writes, Windows and macOS, and `.pze`/`.pse.gz` (which go through `gzip.open` with the same mode).
