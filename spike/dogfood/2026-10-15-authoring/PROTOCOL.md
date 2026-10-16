# 2026-10-15 authoring — the protocol, sealed before the first subject runs (#873)

#861 found three failures beyond truncate-and-replace, each through a hand-written checker that
ran the tool's own recovery and read meaning across files, with a broken state per leg to show it
could fail. #873 asks the next question: **what it costs, and where it goes wrong, to author a
trustworthy semantic checker with Sideeye as shipped** — v1.13.0 and its checker cookbook — before
anything (a DSL, generated checks, an engine feature) is built to make it cheaper.

This page, `prompt.md`, `grader-prompt.md`, `vocabulary.txt`, `CANDIDATES.md`, `exclude.sh`,
`screen.sh` and `tally.py` are sealed in one commit, and that commit is pushed and opened as a
draft pull request **before the first subject runs**. `SELECTION.md` and `cards/` join the seal
after the screen, in a second sealed commit, pushed before the first subject too. The pull
request's creation time and its first check suite are GitHub's clock, not this machine's, and
`tally.py --check` reads both against each transcript's first event (`seal.json`).

## What is reused, and what changed

The apparatus is #618's (`spike/authoring-cost/` at `5510fda3`): one `claude --safe-mode -p`
session per target, started in an empty directory outside every repository, reaching the target
only through `docker exec` into a box with no network; the session's own `stream-json` transcript
as the evidence, normalised the same way; `watch-defines.py` snapshotting every define and the
files beside it. Copied here rather than called, so the seal covers what ran. What changed, and
why:

| #618 | here | why |
|---|---|---|
| engine v1.5.0, read from `spike/unknown-rate/engine-pins.tsv` | v1.13.0, asset and sha256 in `Dockerfile` | #873 measures the release that ships the cookbook |
| the box gets the README from the build's working tree | README, `docs/cli.md`, `docs/checker-cookbook.md`, `docs/apparatus.md` from `git show v1.13.0:` | the tree moves after v1.13.0 (ADR 0136 changed `apparatus.md`) |
| `debian:bookworm-slim` with whatever `apt-get` serves that day | a fixed `snapshot.debian.org` date and `pkg=version` | the target's version is part of what is fixed before exploring |
| the subject writes a define and reaches a verdict | the subject writes the invariant, the recovery, the checker and one control per leg, explores, and lists friction | #873's work breakdown |
| `check-sealed.sh` seals four files and the cards | `check-sealed.sh` here seals every file named above | a decision table outside the seal can be written after the results |
| CI job `authoring-cost` | CI job `authoring-873` | the old job reads only its own directory |

## The subject

One session per selected target, given `prompt.md` with the target, the version, the user
operation and **the contract shape in one sentence** substituted — not the legs. Writing the
invariant down is one of the phases #873 times, so the legs we wrote are the graders' card, not
the subject's brief. The subject starts from the four documents in the box; it is not told to
avoid anything else, because nothing else can be withheld from a session that has the network
on the host (#618's lesson: do not declare a condition that cannot be enforced). What it read is
read back from the transcript.

`--safe-mode` starts the session with CLAUDE.md, hooks, skills, plugins, MCP servers, custom
agents and output styles disabled (`claude --help`). The empty working directory keeps the
operator's per-directory memory out as well.

## The files the subject is asked to leave

In `/home/user/authoring/define/`, flat — the watcher captures that directory and nothing below:
`INVARIANT.md` (the initial valid state, the completed valid state, the admissible crash states,
what the checker deliberately does not claim), `recover.sh`, `check.sh`, one `control-<leg>.sh`
per leg (each builds a state that breaks that leg alone), `sideeye.toml`, and `friction.tsv`
(one row per obstacle: phase, what happened, the command that showed it).

## What is counted

Read from the transcript and the watcher's index by `tally.py`, never typed:

- **judged states** — the engine's `l0` lines of `explore`, as #618 counts them (`audit.py`'s
  parser is imported, not copied). `preflight` lines are a separate column: their shape differs.
- **revisions** — of `sideeye.toml`, of `check.sh`, of `recover.sh`, and of each control, from
  `revisions/index.tsv` and `revisions/scripts/index.tsv`.
- **phase boundaries** — the first appearance of `INVARIANT.md`, `recover.sh`, `check.sh`, a
  control, the first `preflight` that exits 0 or 1, the first `explore`, and the last event.
  Elapsed figures between them are **the transcript's host clock, a model's seconds, published as
  a secondary column and never as a person's time**. The box's clock is not subtracted from it.
- **the result** — the last `explore`'s verdict and reason, whether a FAIL was the checker's or
  the built-in layer's, and its `replay` if the subject ran one.

## Grading

Two graders per target, each a fresh `claude --safe-mode -p` session in its own empty directory
holding only: the sealed card, `grader-prompt.md`, `vocabulary.txt`, the subject's final files,
the revision snapshots, and the transcript with the subject's prompt removed. Neither sees the
other's answer. Each returns:

1. the checker's verdict against the card: `semantically valid` / `wrong question` /
   `vacuous checker` / `unresolved by card` (#618's four, same definitions, `grade-rubric.md`
   there);
2. per control: whether it breaks **its leg and no other** (`yes` / `no` / `unclear`) and one
   line why;
3. per friction row the subject wrote, one key from `vocabulary.txt`, and any obstacle the
   transcript shows that the subject did not list, as an added row with its transcript event.

**Agreement is the unit.** A friction row counts only when both graders give it the same key; a
row one grader added counts only if the other added one with the same key at an event within ten
of it. A checker verdict or a control judgement counts only where both agree; otherwise it is
published as `contested`. Disagreement is a finding, not a gap.

## Disposition

1. **`void`** — the apparatus failed, the box died, the target was not installed, or the subject
   never saw the prompt. Published with its reason and excluded from every figure.
2. **`contaminated`** — the transcript shows the subject reading `spike/dogfood/2026-10-14-mechanisms/`
   or this directory. Counted, and published with the evidence beside every figure it enters.
   #873 asks that the checker not be copied from #861; whether it was is read, not assumed.
3. Otherwise counted.

## The decision

`tally.py` holds the table, first matching row wins:

1. A key other than `target` and `other`, agreed by both graders, in **two or more targets**:
   the next change is the key with the most targets (ties: more rows, then the order of
   `vocabulary.txt`, and RESULTS says it was a tie).
2. Agreed keys, but each in one target only: listed as hypotheses; the next change is
   **no product change warranted**.
3. No agreed row, or only `target` and `other`: **no product change warranted**.

Whatever the row, the graders' agreed `wrong question`, `vacuous checker` and controls that broke
more or less than their leg are listed beside it: whether trustworthy checkers were written is a
second answer, not folded into the first.

## Bounds

Three targets or 2026-10-22, whichever comes first. No DSL, no generated invariants, no power-loss
model, no engine change, no upstream filing. Zero FAILs is a result. **One author, a language
model, per target: this measures authoring by that author with these documents, not third-party
usability or adoption.**

## Amendments

- **2026-10-15, before any subject ran, after the first screen.** The first screen's
  `screen.tsv` is kept as `screen-1.tsv`. Three faults were the screen's own, not the candidates':
  quilt's fixture wrote its patches with a `printf` format beginning `---`, which dash reads as an
  option; the three fixtures written as `exit 1  # reason` lost their closing parenthesis to the
  comment and failed as a syntax error; and python3-yoyo's operation was spelled `yoyo`, a script
  Debian does not ship — the package carries the same entry point as `python3 -m yoyo`, so the
  operation is respelled and the tool, the command and the contract are unchanged. Each is fixed
  once, as #861 allowed a define fixed once, and the screen ran again from the start. slapd and
  python3-flask-migrate still have no fixture: they are reached only if every candidate above them
  in shape 3 is dropped, and that would be a further amendment.
- **2026-10-16, after all three subjects and every grader ran.** `tally.py --check` could not
  pass as sealed, for two reasons the runs exposed and no run caused. `stream-json` opens with
  system events that carry no timestamp, so `events[0]` had none to read; and it does not echo the
  prompt, so "the transcript opens with the seal line" could never hold. The amendment reads the
  first timestamped event, and takes the seal the session was given from `meta.json`, the
  launcher's record — **a weaker witness than the transcript would have been, the same one #618
  had**; what stays GitHub's is that the seal's pull request was opened before each run's first
  timestamped event. `seal.json` keeps the manifest the subjects were given and records this one
  as an amendment; `check-sealed.sh` compares against the latest. The decision table, the
  agreement rules and the counts are unchanged: the diff is in the commit that adds this entry.
  The same amendment corrects two descriptive columns the decision does not read: "result" took
  the last verdict-shaped line anywhere in the transcript (for gdbmtool, a replay's FAIL rather than
  the last exploration's PASS) and "first explore" the first event quoting `sideeye explore` (the
  documents the subject read first); both now come from the subject's own `explore` tool calls and
  their results.
  "result" is the last exploration of `sideeye.toml`, the define the prompt names, and every
  exploration's verdict is listed beside it: gdbmtool's last exploration was a comparison it ran on
  another file, marked so in its own command. An exploration is a tool call whose **command** runs
  `explore` and whose result prints a verdict — not the model's description of the call; a call that
  only quotes the command, such as a heredoc, prints none and is not counted — and a SETUP ERROR, which explored no world, is listed but is not a
  result. This last reading was corrected once more after the first review of this pull request and
  before the amendment was pushed: the first form matched the description and missed two of quilt's
  explorations. `seal.json`'s amendment records the final manifest.
- **2026-10-16, after grading, a second normalisation pass.** The per-directory session path
  (`.claude/projects/-Users-<name>-…`) and `ls -l`'s file owner named the operator's account, which
  `normalise.py`'s home-directory rule does not reach. Both are replaced in every file under `runs/`
  and each touched transcript's `normalisation.txt` says so. No figure reads either string.
- **2026-10-15/16, the weekly usage limit.** gdbmtool's first session and python3-yoyo's first
  session, and quilt's second grader, ended on the account's weekly limit (API 429). They are kept
  as `runs/*.void-weekly-limit/` and `grades/void-weekly-limit-*`, void, and were run again under
  the same seal once the limit reset.
