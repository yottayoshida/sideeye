An interrupted `rubocop -a` leaves the source file at 0 bytes and the original is gone. `ulimit -f 0` reproduces it without a crash:

```
$ wc -c < a.rb
76
$ ( ulimit -f 0; rubocop -a --only Layout/SpaceInsideParens a.rb )
File size limit exceeded
$ wc -c < a.rb
0
```

`File.write(file, corrected_source)` in `finalize_corrections` (`lib/rubocop/runner.rb`, line 449 on `master`) opens the file with `O_WRONLY|O_CREAT|O_TRUNC` and writes afterwards, so between the two the old source is gone from disk while the corrected source is still in memory. A kill, a full disk or a failed write in between leaves an empty file.

Measured on 1.39.0 (Debian 13 package 1.39.0+dfsg-1, aarch64, ruby 3.3.8): `strace` shows one `openat(AT_FDCWD, "a.rb", O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0666)` on the target, and killing the process at each syscall boundary empties `a.rb` at crash point 2 of 4 — after the `open`, before the `write` — in 2 of 5 explored worlds. I read `master` as well as the packaged build: the comment above `finalize_corrections` says the single write replaced the per-iteration writes, which narrows the window to one per file rather than closing it, and the `File.write` call itself is unchanged.

`-a` rewrites the file you point it at, so "write somewhere else" is not something the caller can choose. A committed file can be restored with `git checkout`; uncommitted edits in the same file cannot.

Two possible responses, and I have no stake in which: write to a temporary file in the same directory and `rename` it over the original, or document that an interrupted `-a` empties the file.

<details><summary>How this was found</summary>

With [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project — no commercial interest. It kills the process before each state-changing operation and checks what is left; the checker used here was falsified against deliberately corrupted state before the run, so a check that could not fail did not produce this. If you would rather not have tool-generated reports on this tracker, say so and I will stop. Not measured: power loss, torn writes, concurrent processes.
</details>
