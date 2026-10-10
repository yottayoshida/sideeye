# Predictions — 2026-10-10 uv-threadpool (#686)

Written and committed before any run. #686 asks for one bounded measurement: the thirteen Node targets
it lists, with and without `UV_THREADPOOL_SIZE=1` declared as apparatus, on the same engine, both
results kept. 2026-10-09 follow-ups 3 and 4 measured the *with* side on v1.10.0 — the variable set in
the environment, not declared — and #686's comment says the *without* side was not re-run on v1.10.0.
`apparatus: env:` checks that a value is present and sets nothing (`docs/apparatus.md`), so declaring
it changes no engine behaviour: the with side here is three defines, to see the declared form accepted
and the rebuilt box agree with 2026-10-09.

## Without (13 defines, `preflight`; explored only if the recording is accepted)

All thirteen refuse `multiple_threads_detected` at the recording: joplin, Bitwarden CLI, prettier,
svgo, `npm pkg set`, eslint, stylelint, dotenvx, bibtex-tidy, gemini-cli, vercel, lingui, glTF-Transform.

## With (3 defines, `explore`, the variable set and declared)

| target | 2026-10-09 (set, not declared) | predicted here |
|---|---|---|
| prettier 3.9.7 `--write` | FAIL 1/3 | FAIL 1/3; the report's `apparatus` line names `env:UV_THREADPOOL_SIZE=1` |
| stylelint 17.15.0 `--fix` | PASS 6/6 | PASS 6/6, the same line |
| vercel 62.2.0 `telemetry disable` | UNKNOWN `multiple_threads_detected` | the same |

None of the three is a SETUP ERROR: the declared entry is present in the environment the operation inherits.
