Title: Chunk deletion: the region file is missing if MCA Selector is killed while saving it

**Describe the bug**
After chunks are deleted, `MCAFile.saveWithTempFile` (`src/main/java/net/querz/mcaselector/io/mca/MCAFile.java`, unchanged on `master` at d31bee6a7a) writes the new region to a temp file in `java.io.tmpdir` and then calls `Files.move(temp, dest, REPLACE_EXISTING)`. On Linux the JDK does that move as `unlink(dest)` followed by `rename(temp, dest)`, so for a moment the region file does not exist. A crash or kill there leaves the world without that region, and the only copy of the new one in a randomly named file under `/tmp`.

**To Reproduce** (2.9, `mcaselector-2.9-aarch64.deb`, Debian 13 arm64, command-line mode)

```
strace -f -qq -P "$PWD/world/region/r.0.0.mca" -e inject=renameat:signal=KILL \
  mcaselector --mode delete --world "$PWD/world" --query "InhabitedTime < 1000"
ls -l world/region /tmp/r.0.0.mca*.tmp
```

In my run `r.0.0.mca` was 32,768 bytes before; afterwards it was gone, and a 20,480-byte `/tmp/r.0.0.mca<digits>.tmp` held the new region.

**Expected behavior**
`r.0.0.mca` holds either the old chunks or the new ones.

The README's backup advice covers this, so closing it is fine. Creating the temp file in the region's own directory and passing `ATOMIC_MOVE` would avoid the gap. Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest; say if you would rather not have such reports. Not measured: power loss, and `/tmp` on another filesystem, where the JDK deletes the region first and then copies instead of renaming.
