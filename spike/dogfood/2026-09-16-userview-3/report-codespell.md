An interrupted `codespell --write-changes` leaves the file at 0 bytes and the original text is gone. `ulimit -f 0` reproduces it without a crash:

```
$ wc -c < a.txt
93
$ ( ulimit -f 0; codespell -w a.txt )
FIXED: a.txt
OSError: [Errno 27] File too large
$ wc -c < a.txt
0
```

`codespell_lib/_codespell.py` line 1312 on `main`, and the same line in 2.4.1, opens the file with `open(filename, "w", encoding=encoding, newline="")` — `O_WRONLY|O_CREAT|O_TRUNC` as `strace` prints it — and only then does `f.writelines(lines)`. Between those two points the old text is gone from disk and the new text is still in memory, so a kill, a full disk or a failed write in between leaves an empty file. Killing 2.4.1 at each syscall boundary (Debian 13 package 2.4.1-1, aarch64, Python 3.13.5, `-w` over three files) empties `a.txt` at crash point 2 of 6 — after the `open`, before the `write` — while the other two files stay as they were; 3 of 7 explored worlds ended that way.

`--write-changes` exists to rewrite the file you point it at, so "write somewhere else" is not something the caller can choose here.

Two possible responses, and I have no stake in which: write to a temporary file in the same directory and `rename` it over the original, or say in `--help` that an interrupted run empties the file.

<details><summary>How this was found</summary>

With [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project — no commercial interest. It kills the process before each state-changing operation and checks what is left; the checker used here was falsified against deliberately corrupted state before the run, so a check that could not fail did not produce this. If you would rather not have tool-generated reports on this tracker, say so and I will stop. Not measured: power loss, torn writes, concurrent processes.
</details>
