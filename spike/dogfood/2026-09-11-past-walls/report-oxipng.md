An in-place run that is interrupted leaves the file at 0 bytes, and the original is gone. `ulimit -f 0` reproduces it without a crash:

```
$ wc -c < a.png
12420
$ ( ulimit -f 0; oxipng -o 2 a.png )
File size limit exceeded
$ wc -c < a.png
0
```

`src/lib.rs` (line 254 on `master` and in v10.2.1) opens the output with `File::create`, which truncates it, and only then writes `optimized_output`. By default that file is the input, so from the `File::create` onwards the old bytes are gone while the new ones are still in memory; a kill, a full disk or a failed write in between leaves an empty file. Killing the 10.2.1 release binary at each syscall boundary (Debian 13, aarch64), crash point 2 of 2 — after the `open`, before the `write` — leaves 0 bytes in 5 of 5 runs.

Two possible responses, and I have no stake in which: write to a temporary file in the same directory and `rename` it over the input, or say in `--help` that an interrupted in-place run empties the file.

<details><summary>How this was found</summary>

With [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project. If you would rather not have tool-generated reports here, say so and I will stop. Not measured: power loss, torn writes, concurrent processes.
</details>
