You are operating a fresh Linux machine. Reach it only through this shell form:

    docker exec authoring-box sh -c '<command>'

(For anything interactive-free. Use no other route to the machine.)

On that machine, `/home/user/authoring` contains the README of a tool called sideeye and its
release tarball for this machine's platform. The machine also has `TARGET_NAME` installed — a
real command-line tool you can run.

Your task: **write a sideeye define for `TARGET_NAME` and reach a crash-consistency verdict with
it.** A define says which command to run, which directory holds the state that matters, and what
must still be true about that state after a crash. Set sideeye up from the README, write the
define, and run it until an exploration returns PASS or FAIL.

Two things this task is really asking, in order:

1. get a define that *runs* — a verdict rather than a refusal;
2. make sure the question it asks is the *right* one for `TARGET_NAME` — that what you told
   sideeye to check is what this tool actually promises about its files after a crash.

The second half is the part that matters. `TARGET_NAME`'s own documentation, its `--help`, and
its files on the box are yours to read; use them to decide what a crash may and may not be
allowed to leave behind. A define that runs and asks the wrong question is worse than one that
refuses, because it answers.

Stop when an exploration of `TARGET_NAME` exits 0 (PASS) or 1 (FAIL) **and** you are satisfied
that its question is right for this tool. Then state, in one paragraph: the verdict, the define
you ended with, what you had to learn about `TARGET_NAME` to write it, and anything you are
still unsure about.
