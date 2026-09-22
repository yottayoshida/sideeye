An interrupted `ast-grep scan --update-all` leaves the rewritten source file at 0 bytes and the original is gone. `ulimit -f 0` reproduces it without a crash:

```
$ wc -c < a.js
22
$ ( ulimit -f 0; ast-grep scan --rule rule.yml --update-all a.js )
File size limit exceeded
$ wc -c < a.js
0
```

`rewrite_action` (`crates/cli/src/print/interactive_print.rs`, line 64 on `main`) calls `std::fs::write(path, new_content)`, which opens the file with `O_WRONLY|O_CREAT|O_TRUNC` and writes afterwards, so between the two the old source is gone from disk while the rewritten source is still in memory. A kill, a full disk or a failed write in between leaves an empty file.

Measured on 0.45.3 (the `ast-grep-cli` wheel from PyPI, Debian 13 container, aarch64): `strace` shows `openat(AT_FDCWD, "a.js", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` followed by one `write` of the rewritten file, and killing the process at each syscall boundary empties `a.js` at crash point 2 of 2 — after the `open`, before the `write` — reproduced twice from the saved case. I read `main` as well as the released build; the `std::fs::write` call is unchanged.

`--update-all` rewrites the files you point it at, so "write somewhere else" is not something the caller can choose. A committed file can be restored with `git checkout`; uncommitted edits in the same file cannot, and a codemod is often run over a working tree that has them.

Two possible responses, and I have no stake in which: write to a temporary file in the same directory and `rename` it over the original, or document that an interrupted `--update-all` can empty the files it was rewriting.

<details><summary>How this was found</summary>

With [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project — no commercial interest. It kills the process before each state-changing operation and checks what is left; the checker used here was falsified against deliberately corrupted state before the run, so a check that could not fail did not produce this. This report was drafted with an AI assistant from that tool's output and checked by me. If you would rather not have tool-generated reports on this tracker, say so and I will stop. Not measured: power loss, torn writes, concurrent processes.
</details>
