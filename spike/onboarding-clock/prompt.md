You are operating a fresh Linux machine. Reach it only through this shell form:

    docker exec onboarding-box sh -c '<command>'

(For anything interactive-free. Use no other route to the machine. The machine has no network.)

On that machine, the directory `/home/user/onboarding` contains the README of a tool called sideeye and its release tarball for this machine's platform. The machine also has `jrnl` installed and configured — a real journaling CLI you can run.

Your task: **using only that README as your documentation for sideeye, set sideeye up and produce a crash-consistency verdict for jrnl** — a real exploration of jrnl reaching PASS or FAIL. Treat refusals the way the README tells you to. Do not look for sideeye documentation anywhere else (no other repos, no source reading beyond what the README points you at on the box); jrnl's own `--help` and files on the box are fair game, since jrnl is your tool.

Stop when an exploration of jrnl exits 0 (PASS) or 1 (FAIL), and state in one paragraph: the verdict, the define you used, and what in the README you leaned on or missed.
