Title: `mkdwarfs --recompress -f` with the same file as input and output destroys it

```
mkdwarfs -i src -o img.dwarfs
mkdwarfs -i img.dwarfs -o img.dwarfs --recompress -f
```

The second command prints `no filesystem found` and leaves `img.dwarfs` at 0 bytes (2048 before, `dwarfsck` clean). Without `-f` it refuses, as expected.

At v0.15.8, `mkdwarfs_main.cpp` truncates the output (`open_output_binary`, line 1276) before opening the input for recompression (line 1329). Refusing when both are the same file would avoid it. v0.15.8 aarch64 release.

Disclosure: found while setting up [sideeye](https://github.com/yottayoshida/sideeye), my personal crash-consistency checker; written with an AI assistant (Claude), checked against the runs.
