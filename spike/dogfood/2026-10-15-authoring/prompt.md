SEAL_LINE

You are operating a fresh Linux machine. Reach it only through this shell form:

    docker exec BOX_NAME sh -c '<command>'

(Nothing interactive. Use no other route to the machine.)

On that machine, `/home/user/authoring` holds sideeye v1.13.0's release tarball for this platform
and four of its documents: `README.md`, `docs/cli.md`, `docs/checker-cookbook.md` and
`docs/apparatus.md`. The machine also has `TARGET_NAME` TARGET_VERSION installed — a real
command-line tool.

The user operation is:

    OPERATION

and the contract it is meant to keep is of this shape: **CONTRACT_SHAPE**

Your task: **write a semantic checker for that operation with sideeye, prove the checker can fail,
and explore.** Work in `/home/user/authoring/define/` and keep every file there, flat (no
subdirectories):

1. `INVARIANT.md` — the state before the operation that is valid, the state after it that is
   valid, which states a crash may leave that are still acceptable (after the recovery a user
   would run, if the tool has one), and what your checker deliberately does **not** claim.
2. `recover.sh` — what a user would run after a crash before using the tool again; `exit 0` and
   nothing else if the tool has no such step.
3. `check.sh` — the checker sideeye runs: it runs `recover.sh`, then reads what the tool means by
   its files, through the tool itself where it can, and exits 0 only if the invariant holds.
4. One `control-<leg>.sh` per leg of the invariant: each builds, from the valid starting state, a
   state that breaks **that leg and no other**. Show that `check.sh` rejects each, and accepts the
   valid starting state, the completed state and a recovered one.
5. `sideeye.toml` — the define. Explore it until an exploration exits 0 (PASS) or 1 (FAIL), or
   until it refuses for a reason you cannot remove; if it FAILs, replay the case once.
6. `friction.tsv` — one row per obstacle you met, tab-separated:
   `phase<TAB>what happened<TAB>the command or file that showed it`, where phase is one of
   `setup`, `invariant`, `recovery`, `checker`, `controls`, `explore`, `debugging`.

Start from those four documents. Revise anything — the invariant, a control, the checker — as
often as you need; earlier versions are kept.

Stop when the exploration has its result and every control has been run. Then state, in one
paragraph: the result, what the checker claims and does not, which controls had to be revised and
why, and what you are still unsure about.
