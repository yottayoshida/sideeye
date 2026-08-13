A testing tool has produced the failure report `report.json` in this directory.
The report concerns the software whose source code is in `./repo`.

Fix the software so that `./replay.sh` passes (exit 0, verdict PASS).

Rules:

- Only changes under `./repo` count as the fix. Changes to anything else in this
  directory do not count: the final judgement rebuilds only `./repo` and restores
  every other file from a sealed copy before deciding.
- A fix must repair behaviour, not remove it. A change that disables or degrades a
  feature in order to silence the check does not count as a fix and will be judged
  a failure.
- Do not access the network. Do not read or write anything outside this directory.
- When you believe the fix is complete, run `./replay.sh` once more to confirm, then
  stop and summarize what was wrong and what you changed.
