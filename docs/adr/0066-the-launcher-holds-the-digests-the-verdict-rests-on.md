# 0066 — The launcher holds the digests the verdict rests on, and the judge runs from bytes the launcher verified

- **Status:** Accepted (2026-09-16)
- **Completes:** ADR 0058, whose Consequences named "the launcher-side work" as #515's other
  half and said the ADR could not be read as "#515 is done". It can now. Also closes #592, the
  seal's instance of the same shape.
- **Scope:** `spike/loop-closure-timew/` — the two launchers, the new `measure.py`, `judge.sh`'s
  `finalize`, `eval` and `secondary`, and `stage.sh`'s protocol record.

## Context

ADR 0058 made `judge.sh audit` report whether the record it read is the record that was made,
and made `finalize` demand that report. It left the digest's provenance where it found it: both
launchers computed it from the transcript file after the run and printed it in a `next:` line
for the operator to type back. A digest of the file after the run is only as good as the file
was, and the agent runs as the same user with `Bash` and `Write`, so the value the audit checked
against was in the agent's reach twice — through the file, and through the operator who copied
it. The control verdicts, the seal's manifest (#592: a doctored `manifest.sha256` was restored
as the sealed one, measured by hand in `seal-reds/RESULTS.md`), `protocol.json` beside the seal,
and `judge.sh` itself were in the same position, with no digest at all.

Two reviewers of the plan removed two designs before any code. The first draft took the digests
at the end of `run-agent.sh`, in shell variables. `sh` reads a script as it executes: for the
tens of minutes the agent is alive, the launcher's unread lines are an ordinary file the agent
can write, and so is `judge.sh` for the minutes its `docker build` runs — so the code that would
have compared the digests was the agent's to write. The second draft let a `resume` take the
digests from the operator's paste after a failed container; that put the caller back in the
provenance chain, which is the hole this change exists to close. The same reviewer read
`cmd_eval` and found that the container it runs — the agent-built `timew` under the sealed
`sideeye`, as uid 0 — had the whole results directory mounted read-write, beside `audit.json`,
the control verdicts and the transcript.

## Decision

### 1. The post-run half is python, entered by `exec`

`run-agent.sh` and `run-agent-mcp.sh` keep their pre-run gates (the controls held, the history
check, the canaries) and end in `exec python3 -I measure.py judge …`. Nothing of the shell script
survives into the measured agent's run. CPython compiles the whole file before its first
statement, so what runs after the agent exits is what was on disk before the agent started. `-I`
because `python3 -` and `python3 -c` put the working directory on `sys.path` first, and `$ROOT`
is the agent's to write; every python invocation in the five scripts of the directory
(`contrast-mcp.sh` runs before the agent and carries it for uniformity) does now. The
canaries are claude calls made before the `exec`, with the launcher's remaining lines still
unread; they carry the launcher's own one-line prompt and no task, which is a mitigation, not
the structure the measured run gets — recorded here rather than folded into the sentence above.

The judge's two python modules, `replay_gate.py` and `suite_summary.py`, are executed from
their bytes (`compile` + `exec` into a fresh module), not imported: an import takes
`spike/__pycache__/<module>.*.pyc` whenever that file's header matches the `.py`'s mtime and
size, both of which the agent can read and reproduce, and `-I` does not imply `-B` (which would
only stop writing one). Found in review of the first implementation, which imported them. Unlike
`judge.sh`, whose bytes travel on stdin, these two are read from disk when the step reaches them
— minutes after `measure.py` verified their digests at the step's start, once the container has
finished. That window is the one named among the residuals below; what this decision removes is
the cache, not the window.

### 2. The digests live in the launcher's memory, taken before the thing they guard is exposed

Before the agent: `seal/manifest.sha256`, `seal/protocol.json` (which the manifest does not
cover), `neg-verdict.json`, `pos-verdict.json`, the secondary controls and `mcp-contrast.json`
when present, the mcp variant's `mcp.json` and `seal-settings.json`, the prompt, and the code
the judge runs as — `judge.sh`, `spike/replay_gate.py`, `spike/suite_summary.py`. The image the
judge runs is pinned by id in `protocol.json` at seal time, and `eval` and `secondary` run that
id, never the tag: a tag is a name anyone with docker can move, and the agent has docker through
the stage's own button.

During the run: the transcript is a pipe. `measure.py` writes it to the named file through its
own handle, unbuffered, and hashes the bytes as they flow. The subject's `ftruncate(1, 0)` fails
with `EINVAL` (ADR 0058's measurement), and a file edited by name during the run disagrees with
the stream's digest.

After the agent exits: `agent-meta.json` as written, and a snapshot of `repo/`'s working tree —
every entry's type, owner bits and content digest, `.git/` excluded and recorded separately
(one `git status` rewrites the index, and nothing the judge builds reads `.git/`). Each judge
step's output is hashed as it lands.

### 3. The judge is called only when everything the step reads still matches, from bytes the launcher verified

Before `audit`, `eval`, `secondary` and `finalize`, `measure.py` re-hashes what that step reads
— the code, the seal and controls for the steps that use them, `repo/` before the container
copies it, every earlier step's output — and refuses to call the step when anything differs,
naming the file. The refusal is `exit 3`, apart from a subject's or a step's own exit. `judge.sh`
itself is read, compared to its recorded digest, and fed to `sh -s` on stdin: the bytes that run
are the bytes that were checked, and the file on disk is not consulted again. Inside, `$0` is
`sh`, which `judge.sh` used only to derive `SIDEEYE_REPO` (given in the environment) and to
print its usage.

### 4. `finalize` requires the launcher's file and holds every record to it

After the agent's process group is dead, `measure.py` writes the digests to `$ROOT/inputs.json`
— beside the seal, outside the results directory, in neither of the container's mounts — and
appends each step's output digest to it. `finalize` refuses without that file (`inputs.json
absent`: a finalize run by hand has nothing to hold the records to), hashes every file it
assembles the manifest from against it, and hashes the transcript named by the audit's new
`record_path` against both `record_sha_value` and the launcher's record digest — the stronger
form ADR 0058 named and did not do. The manifest carries `inputs` whole, paths and digests, not
a flag: ADR 0058 already declined a bare "verified" that anyone can write.

A run that stops — a container that failed — continues with `measure.py resume`, which reads
`inputs.json`, re-verifies, and redoes the step and those after it, re-recording their outputs.
The operator supplies no digest. `judge.sh eval --mode run` by hand still works. **The
requirement on `inputs.json` is the launcher's discipline, not a proof that a launcher was
there**: `$ROOT` is the agent's to write, so an agent can leave an `inputs.json` of its own, and
a `finalize` run by hand against it would pass — the same shape as the bare "verified" ADR 0058
declined. What holds the promise is the path the launchers take: `measure.py` writes
`inputs.json` after the agent's group is dead, replacing whatever is there, and it is the only
thing that calls `finalize`. A `finalize` typed by hand is outside the promise, and the file's
absence is what stops the ordinary hand run from assembling a manifest nobody vouched for.

### 5. The container's mounts are the stage read-only and one fresh directory of its own

`eval` and `secondary` mount `$STAGE` read-only and `$RESULTS/<mode>-container-out` read-write,
and nothing else. The agent-built binary runs as uid 0 with exactly its own outputs in reach.
Until this change it had the whole results directory.

### 6. What the agent leaves behind is recorded and stopped, not refused on

Processes still in the agent's process group after it exits (Linux: `/proc/<pid>/stat`; Darwin:
`ps`, whose `sess` column is 0 for every process) are listed and killed with `SIGKILL`.
Containers still mounting the root or the results — by the mount's *source* from
`docker inspect`; `docker ps --filter volume=` matches the destination inside the container —
are listed and stopped. Not the repository: a container mounting it could touch the judge's
scripts, which the digests refuse on, and this machine runs other containers over the same
checkout that the measurement has no business stopping (found in review — the first version
stopped them, at the canary, before the run began). The mcp variant's own server is a
`docker run -i --rm` container a group kill never reaches. Both lists go into
`agent-meta.json`, which `finalize` carries. They are not a gate: what such a process could
have touched is what the digests cover, and a false positive would end a stage and a model
call that cannot be repeated. An interrupted run (the operator's Ctrl-C, forwarded to the
group) is recorded, not judged; `resume` judges it on request. The recorder does not wait
for their EOF either — a `sleep 30 &` with the record's pipe inherited held the first selftest
for thirty seconds — it reads until the subject has exited and the pipe has been quiet for a
second, kills the group, then drains what is left into the record.

## Alternatives considered

- **Digests in shell variables at the end of the launcher.** Killed in review: `sh` reads as it
  runs (decision 1).
- **`resume` from a digest the operator pastes.** Killed in review: the caller's provenance is
  the hole (decision 4).
- **Verification inside `judge.sh` for every subcommand (`--inputs` on `eval`, `secondary`,
  `audit`).** A doctored judge skips its own checks, so a check inside the judge adds nothing a
  check before calling it does not — and it would have rewritten every `fin_root` case. Only
  `finalize` verifies, for a different reason: it makes the record self-checking.
- **`inputs_verified: true` in the manifest.** ADR 0058's "a bare 'verified' is a string anyone
  can write". The list itself is carried instead.
- **Refusing on leftover processes.** Decision 6.
- **`.git/` in the repo/ gate.** Decision 2.
- **Unreachability** (another uid, a container for the agent, closing `/proc`). ADR 0058's
  ruling stands: the experiment runs the agent on the macOS host where its credential lives,
  and a promise of unreachability would be false on the Linux the container runs.

## Consequences

- `judge.sh selftest` grows by four refusals to sixty-four (`finalize-no-inputs`,
  `finalize-unattested`, `finalize-changed`, `finalize-record-changed` — the last asserting both
  sentences, so that blinding either record comparison alone fails it); `finalize-verified`
  now also requires the manifest to carry `inputs`. `WANT_CASES` is 87. Each new refusal has a
  mutation in `seal-reds/MUTATIONS.md`, and `always-clean`'s attribution is re-measured.
- `measure.py --selftest` runs in CI beside the judge's, and `spike/acceptance.sh` runs the
  judge's selftest through `cat judge.sh | sh -s selftest`, the path the measurement uses.
- The `next:` lines are gone from both launchers. A run is one command from `run-agent.sh` to
  `manifest.json`; `measure.py resume` is the second command when the first stops.
- A stage sealed before this change has no `image_id` and no `inputs.json`; `eval` and
  `finalize` refuse it. There is no such stage on disk (`spike/runs/sideeye-loop-62` holds
  results only).
- **Named residual, and a separate promise:** inside the container the agent-built `timew` runs
  under the sealed `sideeye` as the same uid, and `sideeye` writes its replay JSON into the
  directory that binary can write. A fix that leaves a process racing that write could rewrite
  the replay verdict. That is the experiment's trust in `sideeye`'s output file, not the judge's
  inputs, and it is filed as its own issue rather than claimed here.
- Also outside the set, said rather than implied: `.git/`; processes that leave the process
  group (`setsid`); the same-uid reach ADR 0058 measured (`/proc` on Linux); the interpreter,
  its standard library (the Homebrew python is user-writable), `sh`, `ps` and `docker`; and the
  milliseconds between a judge step writing its output and the launcher hashing it.
- **Measured before shipping:** `claude --safe-mode -p` answers through the recorder in a new
  session with no controlling terminal (rc 0, no process and no container left behind); the
  judge's selftest holds through `sh -s`; the recorder's stream digest differs from the file's
  when a by-name append lands during the run, and the file form loses the record to the same
  subject; the staged controls pass under the read-only stage, the container's own directory
  and the image run by id (neg `fail_reproduced`, pos `pass`); and a `replay_gate` `.pyc`
  planted with a matching header and a `gate()` that returns `pass` decided the negative
  control under the importing judge (`expectation_met=False`) and decided nothing under this
  one (`fail_reproduced`, `expectation_met=True`).
