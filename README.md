# sideeye

> *Sideeye doesn't believe it.*

Sideeye is a deterministic skeptic for the coding loop. You declare an invariant — *"if this operation said it succeeded, this must still be true after a restart"* — and Sideeye explores the worlds where your process died partway through, then brings back the **smallest reproducible counterexample**.

It breaks worlds, not inputs: same input, hostile universe.

## Status

**Design phase. There is no code yet.** What exists:

| Document | What it is |
|----------|------------|
| [DESIGN.md](DESIGN.md) | What Sideeye is, and what it refuses to be |
| [PRD.md](PRD.md) | The road from v0.1 to v1.0 |
| [BUILDLOG.md](BUILDLOG.md) | Decisions as they happen, including the wrong ones |
| [CHANGELOG.md](CHANGELOG.md) | Releases (none yet) |

## What it will look like

```
FAIL  case sideeye-000042
invariant  : check.sh exited 1  (always-invariant)
operation  : mytool rotate-key
crash point: after unlink("state/key.json"),
             before rename("state/key.json.tmp" -> "state/key.json")
observed   : doctor: healthy=true / loadable key: none
expected   : doctor's claim matches reality
reproduce  : sideeye replay 000042        (reproduced 10/10)
explored   : 5 crash points, 5 restarts, 5 checks
not tested : power loss, torn writes, concurrent processes
```

The user's side of the contract is three commands and one directory:

```toml
[world]
state = "./state"

[define]
setup     = "mytool init"
operation = "mytool rotate-key"
check     = "./check.sh"        # exit 0 = invariant holds, run after crash + restart
```

## What Sideeye is not

- **Not a property-based testing library.** It varies the world the program runs in, not the input.
- **Not an AI code reviewer.** Verdicts are deterministic; a language model never decides PASS or FAIL.
- **Not a chaos platform.** One binary, ordinary software, local state.
- **Not a certification.** A PASS is a search record, not a safety claim — every report says what was *not* tested.

## v0 scope

Process crash × persistent state consistency, for stateful CLIs and local tools that keep their state in files. Power loss, network faults, clocks, and concurrency are explicitly out of scope for v0 — see [DESIGN.md](DESIGN.md) §9 and §15.

## License

Licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT License](LICENSE-MIT), at your option.
