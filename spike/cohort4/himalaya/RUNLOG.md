# himalaya (cohort 4, target 1): run log

## The invocation the launcher cannot carry

`ops/explore.sh` sets the environment and execs the engine, but the
seccomp profile applies at the container boundary and has to be on the
docker line. Without it `fs::copy` reaches `copy_file_range`, which the
shim does not export and the oracle reports as unsupported, so the run
would refuse rather than measure. The full line:

```
docker run --rm \
  --security-opt seccomp=<repo>/spike/cohort4/seccomp-enosys.json \
  -v <repo>:/work sideeye-cohort4 \
  /work/spike/cohort4/himalaya/ops/explore.sh --json <report path>
```

That the profile is required rather than decorative is measured, not
assumed: `../probes/himalaya-bare.txt` shows the unlifted copy succeeding
through `copy_file_range`, and `../probes/himalaya.txt` shows it falling
back to the libc read/write path with the profile on.

## Timeline

1. **Probe accepted** (#246, main `3d3910e`): every judged condition
   green, interior counted at two engine-reachable kill points.
2. **Define written and drilled** (this PR): the property, the checker,
   and the trials that decided what the checker may use. The operation
   runs once here, un-killed, and the checker is green on what it leaves,
   the state a red checker would cost the target its slot over.
3. **Explore**: not yet run. The mini-seal requires this define to be
   first-parent on main before the engine touches the target, so the run
   and its artifacts land in a separate PR. `proposals.md` states the
   declared world readings before that happens.

## Outcome

r1 refused (`unsupported_syscall_observed: copy_file_range`, exit 2);
`run1/` holds that transcript and its reasoning. The revision that
answers it is `../himalaya-r2/`, which reached a FAIL through the
declared checker. Its results are `../himalaya-r2/RESULTS.md`.
