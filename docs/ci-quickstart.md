# CI quickstart (GitHub Actions)

The example here is not a listing — it is [`.github/workflows/quickstart.yml`](../.github/workflows/quickstart.yml),
a real workflow that runs on every push to main and every pull request in this
repository, against [`docs/ci-quickstart/sideeye.toml`](ci-quickstart/sideeye.toml).
A quickstart that CI itself executes cannot quietly rot into fiction. To adopt
it: copy the workflow, swap the define, invert one gate.

## The three pieces

**1. A `sideeye.toml` next to your project** — the define: where the state
lives, how to produce it, and the one operation to explore.

```toml
[world]
state = "/tmp/myapp-state"        # scratch directory sideeye empties and rebuilds

[define]
setup     = "./ci/seed-state.sh"  # produces the initial state, runs once
operation = "myapp commit"        # explored: killed before each state-changing op
# check   = "./ci/verify.sh"      # optional L2: your own invariant, run after each crash
```

**`state` is sacrificial.** Exploration empties and rebuilds that directory once per
world — hundreds of times in one run — and what comes back is a restore from the
snapshot, with modes flattened and ownership dropped (#121). It is a scratch copy your
`setup` produces, never a directory anything else depends on. This page used to name
`/var/lib/myapp` here; sideeye now refuses a root inside a system tree rather than
emptying it (#267).

If you replay saved cases through the MCP server, know that replay confines the
case's state to `SIDEEYE_MCP_STATE_ROOT` (default: the server root) — a case whose
state lives under `/tmp`, as above, needs `SIDEEYE_MCP_STATE_ROOT=/tmp` on the
server. Widen that variable, never `SIDEEYE_MCP_ROOT`; and with it unset, the
workspace root itself is the declared destruction range (#266, ADR 0022) — so with
it unset, choose a root whose contents you can afford to lose. Since #329 the root
may be a single-component mount (`/work`), but what the vet refuses is a system
location or a directory containing one, never a directory merely because it is
shallow.

Relative paths and place-naming commands (`./x`, `../x`) resolve against the
toml's own directory, so the file means the same thing from any cwd (ADR 0007).
Commands split on spaces — no quoting. An argument that carries a space is
spelled with the argv form, one line, passed verbatim (ADR 0019):
`operation = ["myapp", "commit", "-m", "a message with spaces"]`. A define
spelled as argv skips `sideeye preflight` (flags carry the string form only)
and goes straight to `explore --config`, which answers strictly more.

**2. The workflow steps** — build sideeye (zig 0.16 via `mlugg/setup-zig`),
install `strace` (the completeness oracle; without it a would-be PASS refuses
as `completeness_not_verified` — sideeye does not certify what it could not
fully observe), then:

```sh
zig-out/bin/sideeye explore --config sideeye.toml \
  --shim zig-out/lib/libsideeye_shim.so \
  --oracle /usr/bin/strace \
  --json report.json
```

**3. The gate** — the exit code is the whole integration:

| Exit | Verdict | In CI |
|---|---|---|
| 0 | PASS | Green. Read `not_tested` in the report before celebrating — it lists what this run does not claim. |
| 1 | FAIL | Fail the job. The report's `earliest` object is the counterexample; `replay` is the exact command that reproduces it (shim path included), and the saved case replays with `sideeye replay <case> --shim <lib> [--fresh-state]`. Hand the report to an agent — that loop has been closed end to end, twice (DESIGN §17). |
| 2 | UNKNOWN | **Fail the job by default.** Sideeye refused to judge and `unknown_reason` says why (see [report-schema.md](report-schema.md)). Treating UNKNOWN as green is how a target quietly leaves the tested set. |
| 3 | SETUP_ERROR | Fail the job; the define itself did not run. |

The demo workflow inverts the gate (`test "$rc" = 1`) because its target has a
planted bug — the job proves detection. Your target gates on `= 0`.

The four rows above are the verdicts a run can reach. Commands that produce no
verdict are not in the table and are not gates: `version` and `help` exit 0
because they did what was asked, and a `preflight` that accepts the recording
exits 0 without claiming PASS. `docs/contract-freeze.md` §3 states which
direction the promise runs.

`preflight --twice` uses one more code, and the same reading applies: exit 1
means the two observed runs left different state under `--state` (#199). It is
not a FAIL — no counterexample was found, and none was looked for — it is the
negative answer to the identity question the flag asked, with the differing
paths named. A job that gates on `preflight --twice` therefore treats 0 as "go
ahead and write the define", 1 as "pin what differs first", and 2 as the
detector refusals it already handled. Reading exit 1 from *this* command as a
crash-consistency failure would report a repeatability problem as a bug in the
target's crash behaviour, which is a different claim entirely.

## Notes

- The demo toy finds its state through `TOY_STATE`, which sideeye itself
  exports to its children pointed at the resolved `[world] state` — the
  workflow supplies nothing extra. Your target locates its state its own way
  (env, config, hardcoded path); the toml only tells *sideeye* where to watch,
  and sideeye's children inherit your CI environment.
- One operation per explore, by design: the report must name one command's
  crash window, not an average over several.
- Every field the report carries is documented in
  [report-schema.md](report-schema.md), and CI holds that page to the
  generated reports.
