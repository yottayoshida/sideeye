---
name: sideeye-scout
description: Set Sideeye up on a command-line tool and take it to a verdict — find where the tool keeps its state, propose what must survive a crash, check with `sideeye preflight` that Sideeye can watch it, then run `sideeye explore`. Use when asked whether a tool loses or corrupts its files if it is killed mid-operation, or to write a Sideeye define (a sideeye.toml) for a tool.
---

# Scout a tool with Sideeye

Sideeye kills a program before each operation that can change its saved state, one crash
world each, and checks what is left against an invariant you declare. You read the tool and
propose the question; Sideeye answers it. **Nothing you believe enters a verdict**: PASS,
FAIL and UNKNOWN are deterministic and never consult you.

Hold to these throughout:

- **Propose, never judge.** Do not write "this looks like a bug" anywhere. A belief becomes
  a checker or it stays out of the record.
- **Do not report anything upstream.** Whether a finding goes to a project's maintainers is
  decided before measuring, by the owner; drafting a report is the `sideeye-report` skill.
- **Model.** Measured: Opus 5 or better proposes as well as the hand-written defines; Sonnet
  5 is the floor; a smaller model invents invariants and argv that cannot run. A weaker
  scout cannot touch a verdict, only waste runs.

## 1. Read the tool for five things

From its source, docs, tests and issue tracker:

1. **Where its persistent state lives** — one directory it reads *and* writes. Note what
   is cache or scratch. Sideeye empties and rebuilds the directory a define names for every
   crash world, so the define never names the person's real data: it names a directory the
   setup builds, and points the tool there by the variable or flag the tool reads.
2. **Which commands write that state**, and above all which touch more than one file in
   one operation. Cross-file updates are the richest crash windows.
3. **What its documentation promises** about that state: nothing else is modified, files
   stay consistent with each other, "always a valid X". A promise is checker material.
4. **Whether a fsck / doctor / verify / repair command exists** — a ready-made checker.
5. **Whether its writes look deterministic.** Random IDs or timestamps in names or bytes
   make two clean runs differ; say so up front.

## 2. Propose before defining

At most three candidates, each a state directory, one operation and an invariant, each
with three notes written before any file exists:

- **why** — what could plausibly go wrong if the process dies inside this operation;
- **what property** — the user-visible or documented property the checker represents
  ("the file parses" is not one anyone relies on);
- **where from** — the doc sentence, test or code path the claim came from.

A proposal missing any of the three does not count.

## 3. Write the define

```toml
[world]
state = "./state"                 # a throwaway copy the setup builds; every world replaces it

[define]
cwd       = "."                   # relative arguments resolve here
setup     = "mytool init"         # builds the starting state
operation = "mytool rotate-key"   # the one command Sideeye crashes
check     = "./check.sh"          # exit 0 = the invariant holds after crash + restart
```

- Commands split on spaces with no quoting; an argument with a space takes the argv form:
  `operation = ["mytool", "commit", "-m", "a message"]`.
- Name an executable, not a `#!` script, as the `operation` where you can.
- The define sets no environment: setup, operation and check inherit the one Sideeye is
  started with. If the tool finds its store through a variable, export it before running
  `sideeye`, and list it as `apparatus = ["env:NAME=value"]` so a run without it is refused
  instead of writing somewhere else.
- The check gets the state directory in `$SIDEEYE_STATE_DIR`. Make it **fail closed**: a
  missing file is a failure, an exact match beats a substring, and every failure message
  says which leg refused. Anchor it in the property from step 2. Sideeye corrupts the state
  first and refuses to trust a check that cannot fail.
- If the tool's documented success is a non-zero exit, declare it as a string:
  `expected_status = "3"`.

## 4. Ask preflight first

```sh
sideeye preflight --config sideeye.toml
sideeye preflight --config sideeye.toml --twice
```

The first observes one run: `recording accepted` (exit 0), or a refusal naming the
detector a real run would use, with a `next` line saying what to change (exit 2; 3 when the
define cannot be set up). Follow the `next` line. `--twice` runs it again from the restored
state and names the paths two clean runs leave differently (exit 1): declare those as
`scratch` in the toml if nobody depends on their bytes, or pin what varies and list it as
`apparatus`. Over MCP, where the server lists it, the same question is `sideeye_preflight`
with `config_path` and `twice`; `twice` is refused unless the config's state directory is
inside the server's `SIDEEYE_MCP_STATE_ROOT`. A server without the tool predates it: use
the command line.

## 5. Explore

On Linux, with strace as the second witness:

```sh
sideeye explore --config sideeye.toml --oracle /usr/bin/strace
```

On macOS, the second witness is `--oracle-fs-usage`, which needs `sudo -v` first; without
it:

```sh
sideeye explore --config sideeye.toml --allow-unverified
```

Over MCP: `sideeye_explore_config`. Exit codes: 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR —
capture the code before piping the output anywhere.

- **Treat every UNKNOWN as a define mistake until shown otherwise.** Read its `next` line,
  fix the define, retry. Never weaken the checker to make an UNKNOWN go away; narrow the
  claim instead. A refusal that survives an honest fix is itself the result.
- **`completeness_not_verified` means no second witness ran.** A server without
  `SIDEEYE_MCP_ORACLE` (every server on macOS) answers every would-be PASS with it; that is
  not a define mistake, and a FAIL stands either way.
- **A run with no crash point is a tell**: the state landed outside the declared directory,
  often because the tool finds its store through an environment variable the engine was not
  started with. Without a second witness the exploration says `completeness_not_verified`
  here too; `sideeye preflight` names it `nothing_could_fail`.
- **A PASS over one or two crash points**: check the count against what the operation was
  supposed to touch.
- **A null result is a result.** Record it with the step-2 notes; do not go looking for a
  different question until this one has its answer.

## 6. Hand back

The verdict line, the define, the step-2 notes, and for a FAIL the case path the report
prints. A FAIL on code you can change goes to the `sideeye-triage` skill.

Reference: [the scouting method](https://github.com/yottayoshida/sideeye/blob/main/docs/scouting.md),
[every flag](https://github.com/yottayoshida/sideeye/blob/main/docs/cli.md),
[the MCP server](https://github.com/yottayoshida/sideeye/blob/main/docs/mcp.md).
