A testing tool has produced the failure report `report.json` in this directory.
The report concerns the software whose source code is in `./repo`.

Fix the software so that replaying the saved failure passes (verdict PASS).

To re-check after an edit:

1. Rebuild: run `./build.sh` (it installs the rebuilt binary where the checker
   looks; nothing else picks up your edits).
2. Replay: call the `sideeye_replay_case` tool with `case_path` set to the case
   file named in `report.json`.

Rules:

- Only changes under `./repo` count as the fix. Changes to anything else in this
  directory do not count: the final judgement rebuilds only `./repo` and restores
  every other file from a sealed copy before deciding.
- A fix must repair behaviour, not remove it. A change that disables or degrades a
  feature in order to silence the check does not count as a fix and will be judged
  a failure.
- Do not access the network. Do not read or write anything outside this directory.
- When you believe the fix is complete, rebuild and replay once more to confirm,
  then stop and summarize what was wrong and what you changed.
