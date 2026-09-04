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
   `check`, `marker`, `expected_status`, `cwd`, `apparatus`, `scratch` — the last three added
   after the tag under the additive allowance this paragraph ends with (`cwd`
   recorded in DESIGN §12's fourth facing, with no ADR of its own;
   `apparatus` with ADR 0041; `scratch` with ADR 0043), and named here rather than left to
   the code so the frozen surface and the accepted set stay the same list.
   `apparatus` and `scratch` take only the array form: double-quoted `kind:value` entries for the one, double-quoted paths relative to `state` for the other. Both command spellings: the string
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
   Additive extension stays open (#320): a new optional field may appear in a
   1.x release, so a consumer must tolerate fields it does not know — reading
   this schema as "these fields and no others" is the one reading 1.x does not
   promise. The `unknown_reason` closed set is **not** covered by that
   allowance: it is closed by name, held to the code by a gate, and gaining a
   member after the tag is a breaking change under either reading.

   **Amended 2026-08-30: this promise was broken once, deliberately, by owner
   ruling.** **The version does not record it (2026-09-04):** the release
   carrying it is `v1.1.0`, not `v2.0.0`. That is an owner ruling about what the
   version number is for, not a reading under which the addition stopped being a
   break — this paragraph and the tag would otherwise disagree with nothing saying so. `state_changed_unaccounted` was added after the tag, taking the set
   from 32 members to 33, for #405's detection half — a raw-forked child writing
   into the judged directory reached PASS with its file still there, and no
   existing member could carry the refusal without saying something false about
   the run (the readings are in `surface-changes.tsv`, row `sc-18`). The
   paragraph above is left standing rather than softened: it states what the tag
   promised, and this note states that the promise was not kept. A consumer that
   pinned the set at 32 is entitled to have been surprised. **The rule for
   1.x is unchanged** — the next member needs its own ruling, not this
   precedent, and `sc-18`'s `legality` reads `freeze-broken` for exactly that
   reason: it is not a category of permitted movement, and the ledger would be
   lying if it recorded one.

   **Amended again 2026-08-30: broken a second time, by its own ruling.**
   `trace_budget_exhausted` was added for #377, taking the set from 33 members
   to 34. The engine now holds every live trace under one ceiling rather than
   under a per-read cap counted by call sites, and the refusal that ceiling
   produces is a different fact from `trace_too_large`: there one trace is
   larger than the reader will hold, here every trace involved may be small and
   what ran out is the sum. Reusing the existing member would have changed a
   frozen machine meaning rather than added to the set — a consumer reading
   `trace_too_large` and going to look for one oversized file would find none —
   and that is the same reason `state_tree_too_large` was never folded into
   `state_file_too_large`. Ruled on its own merits, as the paragraph above
   requires: the count of prior breaks was not an argument in it. **Its ledger
   row is a sweep's job, not this change's** — the same reason the paragraph
   above names `sc-18` for a row `surface-changes.tsv` does not yet hold. That
   ledger ends at `sc-17`, and the gap is the designed state rather than a debt:
   the ledger is compared against the surfaces *as the pin reads them*, so a row
   for a change made after the pin fails `check-freeze-audit.sh` outright. The
   script says so where a reader meets it — "if your own change is what moved
   the surface, that is not your job either … the pin asserts a reading you have
   not taken. Leave both alone." A row written early was tried once and reverted
   (BUILDLOG, "the freeze ledger row was a PR too early"), and this change
   started down the same path before the gate stopped it. Both rows arrive when
   a sweep re-reads the surfaces and moves the pin in one commit. **The rule for
   1.x is still unchanged**, and a third member would need a third ruling; two
   is not a pattern that grants the next one.
3. **Exit codes.** When a run produces a verdict, that verdict's exit code is
   fixed: 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP_ERROR — and UNKNOWN is never 0.
   The promise runs in that direction. **Exit 0 is not reserved to PASS**: it
   is the success of whatever was asked for, and a command that produces no
   verdict at all can use it. `version` always has; `help` does too (#273);
   a preflight that accepts the recording exits 0 without claiming PASS. What
   the freeze forbids is a verdict arriving under a different code than the
   one named above, or exit 0 being read as proof that a check ran — which is
   why UNKNOWN never takes it.
   **No evidence-strength split** (owner decision, 2026-08-17): an
   unverified PASS keeps exit 0, rejected because the flag that produces it
   is the caller's own explicit consent, macOS — where no oracle exists —
   would lose exit-0 passes entirely, and the distinction already lives in
   the designed channel (`oracle_verified`). Declining now means declining
   permanently; that is understood. That decision is about which code a PASS
   carries, and is untouched by the paragraph above.
4. **Replay compatibility.** A saved case replays across 1.x or refuses
   honestly — `case_no_longer_applies`, whether the code changed underneath
   it or the trace contract did (the refusal message names which) — never a
   verdict about a shifted address (ADR 0009, 0014). An earlier revision of
   this paragraph split the two conditions across two reason names; measured
   against the code, both answer `case_no_longer_applies`, and
   `contract_version_mismatch` is a different refusal entirely — a shim and
   engine speaking different trace versions inside one run, nothing to do
   with saved cases. Version and shape travel together (a v1/v2 case cannot
   carry an argv command). From version 5 (ADR 0043) a case also spells both
   keys the top of the ladder introduced — `cwd` as `null` when none was
   declared, `scratch` as a non-empty array — because a version holding two
   independent optional fields cannot be held honest by the one-field gate
   version 4 used;
   a v5 file missing either key, or an older file carrying `scratch`, refuses
   as malformed. A future trace-contract bump is therefore *not* a
   broken promise: old cases refuse with the mismatch named, and that
   refusal is the promised behavior.
5. **The MCP surface** (decided 2026-08-13, recorded in #86, codified here).
   The two tool names — `sideeye_explore_config`, `sideeye_replay_case` —
   their input schemas, and the isError derivation rule (isError follows the
   verdict structure: real verdicts false, refusals true — ADR 0010).
   Additive extension stays open: new tools, new optional parameters.
