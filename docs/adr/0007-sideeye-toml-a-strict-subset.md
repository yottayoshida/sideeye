# ADR 0007 — sideeye.toml is a strict subset, hand-parsed, and owns only the define surface

- **Status:** Accepted (2026-08-12)
- **Supersedes:** nothing. Gives DESIGN §12's "three commands and one directory" its
  file form; flags remain valid
- **Scope:** a new `src/config.zig`, the `--config` flag, and the exclusivity rule
  between the file and the define-surface flags

## Context

Every real target so far has been driven by a hand-written recipe script whose whole
job is to spell five strings: the state directory, a setup command, the operation, a
checker, and (soon) a success marker. DESIGN §12 promised those five as a
`sideeye.toml` and called the contract a budget: "if Define ever needs more than
this, that is movement toward the kill criteria in §18, and we should notice."

A config parser is where that budget is either enforced or silently spent. A
full TOML dependency accepts arrays, tables, dotted keys and escapes whether the
contract wants them or not — the parser's width becomes the contract's width, and
nobody decided that. It is also a supply-chain surface in a tool whose one job is to
be trusted about verdicts.

## Decision

1. **A hand-written parser for a strict subset.** Accepted forms: `[world]` and
   `[define]` section headers, `key = "double-quoted string"` pairs, blank lines,
   `#` comments (full-line, or after a value — DESIGN §12's own example writes
   inline comments). Everything else is a SETUP ERROR that names the line and the
   problem. Unknown sections, unknown keys, bare values, duplicate keys, empty
   values and escape sequences all refuse. An ignored key would be a declared
   invariant that silently never fires — this tool's worst shape, in config form.
2. **Keys exist only once they are enforced.** The v0.3 schema is
   `[world] state` and `[define] setup / operation / check`. `marker` joins the
   schema in the PR that makes L1 judge something; until then it is an unknown key
   and refuses. A key that parses before it acts would accept a declared invariant
   and quietly not enforce it.
3. **The file owns the define surface only.** `--shim`, `--oracle`, `--work`,
   `--json`, `--allow-unverified` are machine-local operation, stay flags, and
   combine freely with `--config`. The define-surface flags (`--state`, `--setup`,
   `--operation`, `--check`) are mutually exclusive with `--config`: the define
   lives in one place or the other, never merged. A precedence table would have to
   be remembered, and a config whose lines may or may not be in effect cannot be
   read on its own.
4. **Paths resolve against the toml's directory**, not the process cwd, so the same
   file means the same thing from anywhere. `state` resolves when relative. Command
   strings resolve their argv[0] only when it contains a `/` and is not absolute
   (`./check.sh` becomes `<toml-dir>/./check.sh`); a bare name (`mytool`) stays a
   PATH lookup.
5. **Command strings split on spaces, no quoting, no escapes** — the same rule the
   flags have always had, now written down. An argument that needs a space needs a
   script file, and the parser says so instead of guessing.

## Alternatives considered

- **A TOML dependency** — rejected: the accepted grammar would exceed the contract
  by construction, and it adds a supply-chain surface to a trust tool.
- **JSON config** — rejected: DESIGN §12 names `sideeye.toml` as the artifact, and
  comments are part of how defines document themselves.
- **Flags override config (precedence merge)** — rejected: which line is in effect
  becomes invisible; drift between the two sources is exactly the class of quiet
  divergence this tool exists to refuse.

## Consequences

- A define is one reviewable, replayable file; recipes shrink to a toml + a checker.
- The parser is ~100 lines that must themselves be tested fail-closed (the
  acceptance suite pins unknown-key, bare-value and exclusivity refusals).
- Future keys (`marker`, and whatever v0.4+ earns) each arrive with the change that
  enforces them, keeping the budget observable one key at a time.
