Title: A target that depends on its files' permission bits cannot be measured, and preflight tells the user to change the define

Filed-under: reach

Restore puts back names, bytes and link targets but not permission bits: the report says so on its `metadata` line ("crash worlds run at the engine's default modes"). A target whose behaviour depends on a mode in the judged directory therefore runs differently in the second recorded run than in the first, and `preflight --twice` refuses with `recording_run_failed` and the next step *"Change the define: the detail above names the declaration this run contradicted"*. There is nothing in the define to change.

Measured on v1.7.0 (aarch64 Linux, the installer's release), 2026-10-03 user-data dogfood run:

- **A probe** (`spike/dogfood/2026-10-03-user-data/apparatus/probes/modebit/`): the operation is a `0755` script inside the state root. The first run succeeds; the second fails with `strace: exec: Permission denied`, and the file is `0644` afterwards.
- **upx** `-q prog` on a copy of `/usr/bin/bash`: the second run exits 1, `CantPackException: file not executable`.
- **argocd** `context work --config config` with the config at `0600`: the second run exits 20, `config file has incorrect permission flags -rw-r--r--`.

Who meets it: anything that refuses or changes behaviour on a mode — executables, and credential files that tools insist be `0600`/`0400` (argocd, ssh, gocryptfs's `gocryptfs.conf`).

Two directions, in increasing cost: name the case in `next` (the second run's failure differs from the first and a mode in the state root differs from the snapshot), and list it under "What the target has to be" in the README; or snapshot and restore modes within the state root.

Records: `spike/dogfood/2026-10-03-user-data/RESULTS.md`, `transcripts/probe-modebit.txt`, `transcripts/entry-out/entry/{upx,argocd}.preflight.txt`.
