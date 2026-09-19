# The apparatus pilot — everything except the subject

`run-authoring.sh` had never executed when this merge was written, and a launcher that has only
been read is a launcher that works in theory. This is the dry run: the box, the watcher, the
copy-out and the audit, driven end to end with a **scripted subject** — a sequence of
`docker exec` writes standing in for the session.

Committed under `pilot/apparatus/`:

| file | what it shows |
|---|---|
| `revisions/01..03.toml` | the watcher caught three defines, **including one that was never run** — a define written and replaced two seconds later, which a wrapper around `sideeye` could not have seen |
| `revisions/index.tsv` | its own account: order, timestamp, digest, path |
| `transcript.jsonl` | a transcript of the shape the launcher writes, carrying a verdict |
| `meta.json` | `disposition: void` — see below |

`audit.py` on it reads: 3 revisions, `runnable_elapsed_s: 360`, no repository traces,
`semantic_status: contested-or-ungraded` (nothing was graded, because nothing was authored).

## What this is not

**It is not a run, and it is void by construction.** No subject authored anything: the defines
were typed by the apparatus. `dos2unix` appears in it only as a string inside a scripted file —
the target's freshness is untouched, nothing was explored, and no card was consulted.

**It does not exercise `claude --safe-mode -p`** — but something else did. The void run in
`runs/dos2unix/` is that call, end to end, by accident: a real session, its transcript
normalised and published, its defines caught by the watcher and copied out. So the launcher has
now run whole, once, and the piece this pilot skips is the piece that run covers.
What the pilot does cover is everything the session's evidence depends on: that the watcher runs
as the box's main process and survives `docker exec` writes, that `docker cp` brings the
snapshots out intact with their index, that the audit's refusals do not fire on well-formed
evidence, and that the figures it publishes are derived rather than typed.

The launcher's refusal paths were exercised separately, and the record of that is mixed:

| refusal | exercised |
|---|---|
| a target with no sealed card | yes — `run-authoring: no sealed card for notatarget`, exit 1 |
| a seal that does not verify | yes — `run-authoring: the seal is not intact; nothing was run` |
| a target the selection does not name | **not exercised as intended**: the check matched the package against the wrong column of `selection.tsv`, so it refused every target including the four selected ones. Fixing it is what let the void run start |
| a run directory that already exists | **not fired**: it sits after the selection check, and by the time that was correct the run had begun |

The two that fired did so before anything was spent. The two that did not are the reason
`runs/dos2unix/` exists at all, and they are written here rather than described as covered.
