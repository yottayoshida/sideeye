Title: seconv `--overwrite` empties the input subtitle if it is interrupted while writing

With `--overwrite`, seconv writes the converted text back over the input with `File.WriteAllText` (`SaveTextFormat` in `src/seconv/Core/LibSEIntegration.cs`, unchanged on `main` at c3fc91591e), which truncates the file before it writes. If the process is killed between the two, the only copy of the subtitle is left empty.

**To reproduce** (SeConv 5.2.0, `SeConv-Linux-ARM64.tar.gz`, Debian 13 arm64):

```
printf '1\n00:00:05,000 --> 00:00:07,000\nHello\n\n' > subs.srt
strace -f -qq -P "$PWD/subs.srt" -e inject=pwrite64:signal=KILL \
  seconv subs.srt subrip --offset:-2000 --overwrite
ls -l subs.srt
```

`strace` kills seconv at its first write to `subs.srt`, after the truncation. `subs.srt` goes from 39 bytes to 0.

**Expected:** `subs.srt` holds either its old text or the new one.

Writing to a temporary file next to the input and renaming it over would avoid it. Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest; say if you would rather not have such reports. Not measured: power loss, and output formats other than SubRip, which go through the same `File.WriteAllText` calls.
