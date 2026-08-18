# The contract freeze — what v1.0 promises not to change

This page is the **normative declaration** of the five surfaces frozen at
the v1.0 tag. It was written by the contract-freeze audit (#86,
`docs/freeze-audit.md`) and moved here because the audit page retires at
the tag while the promise does not — a freeze whose only home is a retired
page is a freeze nobody can read. Before v1.0, all of these may change in
any release (the CHANGELOG's standing header says so); the tag flips that
sentence — from then on, changing any of them is a breaking change.

The audit that preceded this declaration — every open issue classified
against these surfaces, every toucher fixed or documented before the
freeze, twice (the original sweep 2026-08-17, the pre-tag re-sweep
2026-08-18) — is recorded with its adjudications on the audit page.

## The five surfaces

1. **Config format.** `[world] state`; `[define] setup`, `operation`,
   `check`, `marker`, `expected_status`. Both command spellings: the string
   form with its split-on-spaces, no-quoting rule, and the argv form — one
   line, double-quoted elements, passed verbatim (ADR 0019). Unknown keys,
   malformed values and the array form on non-command keys refuse with named,
   line-numbered errors; relative paths resolve against the toml's directory
   (ADR 0007). Additive keys remain possible; changing the meaning of an
   accepted spelling does not.
2. **Report schema.** The fields, presence rules and `unknown_reason` closed
   set documented in `docs/report-schema.md`, held to the code by acceptance
   check 4 — `oracle_verified` included (#94). The account fields' prose may
   improve between releases; their presence and the machine fields' meaning
   may not (a field would change name, never silently change meaning).
3. **Exit codes.** 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP_ERROR — and UNKNOWN is
   never 0. **No evidence-strength split** (owner decision, 2026-08-17): an
   unverified PASS keeps exit 0, rejected because the flag that produces it
   is the caller's own explicit consent, macOS — where no oracle exists —
   would lose exit-0 passes entirely, and the distinction already lives in
   the designed channel (`oracle_verified`). Declining now means declining
   permanently; that is understood.
4. **Replay compatibility.** A saved case replays across 1.x or refuses
   honestly — `case_no_longer_applies` when the code changed underneath it,
   `contract_version_mismatch` across trace-contract versions — never a
   verdict about a shifted address (ADR 0009, 0014). Version and shape travel
   together (a v1/v2 case cannot carry an argv command). A future trace-
   contract bump is therefore *not* a broken promise: old cases refuse with
   the mismatch named, and that refusal is the promised behavior.
5. **The MCP surface** (decided 2026-08-13, recorded in #86, codified here).
   The two tool names — `sideeye_explore_config`, `sideeye_replay_case` —
   their input schemas, and the isError derivation rule (isError follows the
   verdict structure: real verdicts false, refusals true — ADR 0010).
   Additive extension stays open: new tools, new optional parameters.
