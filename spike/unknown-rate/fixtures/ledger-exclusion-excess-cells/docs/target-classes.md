# Which tools Sideeye can judge (fixture for count.py's class-exclusion check)

## Measured, with verdicts

| Class | Tool | What happened | Recorded in |
|---|---|---|---|
| C CLI | toyA 1.0 | **FAIL** | `spike/unknown-rate/defines/toyA/def.txt` |

## Refusals that are the correct answer

| Class | Tool | The named wall | Recorded in |
|---|---|---|---|
| Fixture refusal class | fx 1.0 | `no_shim_marker` | spike/cohort2/fx/ops/fx.toml |
| Other refusal class | other 2.0 | `open(f, O_WRONLY|O_CREAT)` | spike/cohort2/other/NOTES.md |
