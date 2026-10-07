# 0095 — A command spelled for a shell runs as written, with a warning

- **Status:** Accepted (2026-10-06)
- **Refs:** #706 (from the 2026-10-05 whole-product review, measured with the v1.8.0 brew binary
  on macOS arm64); ADR 0007 (the string form splits on spaces, no shell); ADR 0019 (the argv
  form); ADR 0041 (`apparatus`, whose presence rule this field follows); #597 (the seal, whose
  placement the stderr line follows); `docs/contract-freeze.md` surfaces 1 and 2.
- **Scope:** `src/config.zig` (`shellWarnings`, `shellWarning`, `fixedLine`), `src/report.zig`
  (`define_warnings`, `sayWarnings`, `emitWarnings`), `src/main.zig`, `src/refuse.zig`,
  `src/mcp.zig`, `spike/acceptance.sh`, `docs/cli.md`, `docs/report-schema.md`,
  `docs/contract-freeze.md`.

## Context

A string-form command is split on spaces and run without a shell (ADR 0007). The README says
so, and ADR 0019 gives the argv form for an argument with a space. Still, a define written the
way a shell reads one — `operation = "./kva ./state name 'hello world'"`, or `"… && echo ok"` —
runs a different argv than its author meant: the quotes reach the program as characters and
`&&` as an argument. The review measured both, and both PASSed. A study subject in
`spike/onboarding-clock/RESULTS.md` missed the rule the same way. A toml value the parser
refused — `expected_status = 0`, `state = './state'` — was told "the value must be one
double-quoted string" without the line that would have worked.

## Decision

1. **Run it as written; warn.** A string-form setup, operation, check or recovery command
   that holds a quote, or a whole unquoted word a shell would act on (`&&`, `||`, `|`, `|&`,
   `&`, `;`, `(`, `)`, a redirection with or without an fd number, a word beginning `$` or
   `~/`, a lone `~`, a backquote, a leading `NAME=value`), earns one sentence saying how
   Sideeye reads it. For quotes it gives the argv form that groups what they meant — as the
   toml line, or for a flag as the line a sideeye.toml would take — when that argv can be said
   exactly; a `[recovery]` command, which has no argv form, and a word the argv form cannot
   spell (empty, or holding a `"` or `\`) are pointed at a script. A backquote, or a `$`
   followed by a name, `{`, `(` or a special parameter — inside double quotes or unquoted
   mid-word (`--out=$HOME/x`) — is an expansion a shell would have made: that word gets the
   "nothing expands it" sentence and no argv, which would carry the unexpanded text as if it
   were the meaning. A `$` with no such follower (`^x$`) stays a `$`; a glob is not looked at.
   Nothing about how the command runs changes.
2. **Only whole words.** A symbol inside a word — `x=n*10`, `ggiX<esc>`, `~>1.6`,
   `%(title)s`, four defines this repository runs — means what it says to a program run
   without a shell, and is not named. A quote around a `|` is a quote: the sentence names the
   quotes, not a shell.
3. **Where it is said.** In the report (`warning`), the JSON (`define_warnings`, present only
   when there is one), `sideeye mcp`'s summary, and Sideeye's standard error as
   `sideeye: warning: …` — written once, at the end, beside the seal, so a reader of merged
   output who takes its first line still finds the verdict (the reason the seal sits there).
   The stderr line is what reaches a run that ends in a SETUP ERROR, whose text is one line,
   and `preflight`, which writes no JSON. Every piece of the command quoted goes through
   `textShown`; a flag's value never met the toml's byte discipline.
4. **Not on a replay.** Its case holds commands an exploration already read, and a toml-born
   case holds argv[0] resolved to a path whose directory could hold a quote of its own.
5. **The parser's refusal carries the fixed line.** "the value must be one double-quoted
   string" gains `; write it as: <line>` when there is a line that parses back as one value the
   writer could have meant: a single-quoted or unquoted value double-quoted, a trailing comment
   (after a space) kept, and a command whose inner quotes group words written in the argv form
   (`\"` read as a quote). No line where the value reads two ways with different argvs
   (`"a" "b"`), or where the value or comment holds a byte `textShown` would rewrite — the
   refusal prints toml text the parser never vetted, and must not print it raw.
6. **A command value cut by a comment is said.** `check = "grep -c "#include" f"` has always
   parsed as `grep -c ` with the rest a comment (the first `"` after the value closes it, and
   `#` right after opens a comment). Refusing it would change what an accepted line means, so it
   stays accepted; the parser records a sentence saying what the command became and, where the
   inner quotes give one, the argv form — added to the define's warnings ahead of the rest.

## Alternatives considered

- **Refuse such a command as a SETUP ERROR.** Declined by the owner (2026-10-06): it would also
  refuse spellings that work today and mean what they say — an unquoted `a|b` handed to
  `grep -E`, `^x$` — and surface 1 of `docs/contract-freeze.md` freezes the meaning of an
  accepted spelling.
- **Print the warning to stderr when the define is read.** Rejected: it would become the first
  line of merged output, which `docs/cli.md` promises is the verdict.
- **Only the report line.** Rejected: a setup that fails over its quotes ends in a SETUP ERROR,
  whose text has no room for it, and preflight writes no JSON — the two runs that most need it
  would show nothing.
- **Count every shell metacharacter, inside words too.** Rejected: it named four defines this
  repository runs that work as written. Some whole words that are counted mean what they say
  to a program as well — `find`'s `;` and `(`, an unquoted `$p` for `sed` — and earn the
  sentence anyway: it says the word reaches the program as written, which is true, and the
  advice is conditional on wanting a shell. A version constraint `>=1.6` is not counted.
- **Point a `NAME=value` prefix at `apparatus`.** Rejected in review: `apparatus` declares and
  checks, it does not set ("Sideeye applies none of it", `docs/cli.md`). The sentence names
  `env NAME=VALUE program`.

## Consequences

- `define_warnings` is one optional field under surface 2's allowance; `contract_version` does
  not move. The terminal gains lines only for a define that earns them.
- Not seen: a glob (`*`, `?`), a brace, an escape outside quotes, a symbol inside a word. Each
  passes as written, as before; the docs say so.
- `demo` passes paths it built under the temporary directory as string-form flags; a
  temporary directory whose name holds a quote or begins with `$` would earn the demo a warning
  about its own commands — true, and harmless.
