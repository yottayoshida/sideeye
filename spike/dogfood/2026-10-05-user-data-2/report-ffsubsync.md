Title: `--overwrite-input` empties the subtitle file when the write fails

**Environment:**
 - OS: Debian 13 (trixie), aarch64
 - python version: 3.13.5
 - subsync version: ffsubsync 0.5.1

**Describe the bug**
With `--overwrite-input`, `write_file` (`ffsubsync/generic_subtitles.py`, unchanged on master at de310ac) opens the input with `"wb"` before writing, so a failed write leaves the only copy empty.

**To Reproduce**
`ulimit -f 0` (standing in for a full disk), then `ffsubsync ref.srt -i movie.srt --overwrite-input`.

**Expected behavior**
`movie.srt` keeps its old timings.

**Output**
`OSError: [Errno 27] File too large`, exit status 0, `movie.srt` 2,500 → 0 bytes. Killing the process between the open and the write does the same.

Writing to a temporary file and `os.replace` would avoid it. Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest; say if you would rather not have such reports.
