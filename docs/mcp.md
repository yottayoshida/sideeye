# The MCP server

The README gets a person to a first verdict at the command line. This page is the same engine driven by an agent over MCP: what the server reads, what it confines and what it does not, and a first call that CI runs against the built server.

<!-- CI reads the section below by its exact heading. spike/check-readme-mcp-call.sh runs its one sh fence and its one jsonrpc fence against the built server, and spike/check-mcp-env.py holds its table to src/mcp.zig. Keep the heading at level two, and add no second sh or jsonrpc fence inside that section. -->

## Driving it from an agent (MCP)

`sideeye mcp` is a stateless MCP server (stdio) with two tools: `sideeye_explore_config {config_path}` and `sideeye_replay_case {case_path}`. The tools take *paths* inside `SIDEEYE_MCP_ROOT`, never raw commands — the config file is the trust boundary you vet, **and a saved case is the same boundary**: its setup/operation/check are executed on replay, exactly as a config's are on explore. The root confines which config or case may be named, not what its commands do: run the server inside a container, network-off where the target allows it. **The server does not check that you did**, and #328 measured why a check would not help: the observations that *do* move with confinement can be raised by the process being confined — a `Seccomp` filter costs two `prctl` calls and no capability at all, Docker's masked `/proc` mounts cost `CAP_SYS_ADMIN`, which the unconfined process is the one to have — and none of them says anything about the mount the root came in on. A container reading maximally confined by every one of them (`/.dockerenv` present, `Seccomp: 2`, ten masked `/proc` entries, no extra capabilities, its own PID namespace) destroyed a file on the host through a bind-mounted root — the shape this page recommends. **What the containment cannot do for you is make the root safe to lose**: pick that directory as if a replayed case will empty it, because one can. A single-component mount is fine (`/work`, `/repo` — a directory the container exists to hold); what the server refuses at startup is `/`, a system tree or scratch parent (`/usr`, `/var/lib`, `/tmp`), **and any directory that contains one** — so `/var` and, on macOS, `/private` are refused for holding `/var/lib` and `/private/tmp`. The denylist stops the mistake that has a name, not every bad choice: **with `SIDEEYE_MCP_STATE_ROOT` unset the root is also the declared destruction range**, so name a directory whose contents are yours to lose — `/opt` passes the vet and is where installed software lives. One thing more IS confined (#266): the state directory a replayed case names — the directory replay empties and rebuilds — must resolve strictly inside `SIDEEYE_MCP_STATE_ROOT` (default: the root). Cases made at the CLI conventionally keep state under `/tmp`; set `SIDEEYE_MCP_STATE_ROOT=/tmp` to replay them through the server. Widen that knob, never the root (ADR 0022).

A deployment that follows from the above, rather than only from the word "container":

```
# --network=none where the target allows it; --read-only and --cap-drop bound what a
# target can do to the image; --tmpfs /tmp:exec is required, not decoration — the work
# directory defaults to /tmp/sideeye-mcp and the engine execs from it; the -v mount is
# a directory made FOR this, holding nothing else.
docker run --rm -i \
  --network=none \
  --read-only --tmpfs /tmp:exec \
  --cap-drop=ALL --security-opt no-new-privileges \
  -v "$PWD/sideeye-work:/work" \
  -e SIDEEYE_MCP_ROOT=/work \
  your-image sideeye mcp
```

The mount is the part that matters and the part a container cannot make safe: everything reachable through it is reachable by a replayed case's commands. Give the server a directory created for it — not your repository, not your home, not a checkout you would mind losing — and treat its contents as already gone. `--read-only` and `--cap-drop=ALL` bound what a target can do to the *image*; nothing bounds what it does inside the root you handed it, which is why `SIDEEYE_MCP_STATE_ROOT` exists (ADR 0022) and why it is the knob to narrow first.

### The first call

The server speaks MCP schema **2026-07-28**. Two consequences a client written against an older mental model will meet immediately: there is no `initialize` — the server exposes `server/discover`, and `tools/list` works without either — and **`_meta` is per-request and mandatory**, with the protocol version and client capabilities under their namespaced keys exactly as spelled below.

Everything the server reads from its environment:

| Variable | Required | Meaning |
|---|---|---|
| `SIDEEYE_MCP_ROOT` | **yes** | The directory tool paths are confined to, vetted at startup (above). |
| `SIDEEYE_MCP_SHIM` | no | An override. Unset, the server looks where the README's install note says it looks: beside the binary, then `../lib` — the same order the CLI uses, so a tarball and a Homebrew install both resolve with nothing set. Until #389 this command demanded the variable instead, which made it the one place the product did not do what that sentence promises. **The search declines what it cannot attribute** (#423, ADR 0044): a candidate that is a symlink, or that belongs to none of {you, root, the owner of the `sideeye` binary}, is refused by name rather than used, and the refusal says which of the two places it was and how to get past it. This is a mitigation and not a boundary — what is checked is a pathname, and the dynamic linker resolves that pathname again when the child starts, so anyone who can write the install directory between the two has not been stopped. Where that directory is not yours alone, set this variable, or fix the permissions. |
| `SIDEEYE_MCP_STATE_ROOT` | no | Where a replayed case's state directory may live. Default: the root (ADR 0022). |
| `SIDEEYE_MCP_WORK` | no | Scratch for traces and cases. Default `/tmp/sideeye-mcp`. |
| `SIDEEYE_MCP_ORACLE` | no | The second witness. Without one a would-be PASS refuses as `completeness_not_verified`; a FAIL stands on its own evidence either way. |
| `SIDEEYE_MCP_CHILD_ENV` | no | Comma-separated names of variables to pass through to the target. Nothing else reaches it (ADR 0011). |

One value is yours to supply, and it is written as `/path/to/…`. Nothing else has to be set:

```sh
export SIDEEYE_MCP_ROOT=/path/to/your/workspace
```

With a `sideeye.toml` in that workspace — the README's Usage section shows the shape; fill it in for your own tool — this reaches a verdict, or refuses with a named reason:

```jsonrpc
{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}},"name":"sideeye_explore_config","arguments":{"config_path":"/path/to/your/workspace/sideeye.toml"}}}
```

`isError` follows the verdict structure, not the outcome: a FAIL is a real answer and comes back `false` (ADR 0010). **Both blocks are run on every pull request and every push to main, extracted from this page, against the built server, with nothing else in the environment** — on Linux as `spike/mcp-acceptance.sh` check 15 and on macOS as a step of its own, both calling `spike/check-readme-mcp-call.sh`. They are a record of what the server does today, not an addition to the frozen surface — what v1.0 froze is the two tool names, their input schemas and that `isError` rule (`docs/contract-freeze.md`, surface 5).

Measured here, not aspirations: a context-free agent, handed a counterexample and bug-blind replay plumbing, produced the fix — twice: once through the CLI, once through this MCP server (`spike/loop-closure-timew/`) — an LLM scout authored the defines for five real targets under a fixed protocol (`spike/assisted/`; the method: [docs/scouting.md](scouting.md)), and a context-free agent set Sideeye up **from the README alone** — tarball to a real verdict on an external tool in under five minutes, protocol declared before the clock, measured twice (`spike/onboarding-clock/`: run 1 at 4 m 22 s, 2026-08-17; run 2 at 2 m 55.7 s, 2026-08-28, against the README as it stood at the freeze — the criterion's evidence).
