Title: `helm repo remove` leaves `repositories.yaml` empty when its write fails or the process is killed before the write

### What happened?

`helm repo remove` rewrites the repositories file with `os.WriteFile`, which truncates it and then writes. If that write fails — a full disk, a quota, `ulimit -f` — or the process is killed between the two, the file is left at 0 bytes. Every repository entry is gone, with any credentials stored in it, and nothing else holds a copy.

```console
$ ( ulimit -f 0; helm repo remove b --repository-config repositories.yaml --repository-cache cache ); echo "exit $?"
Error: write repositories.yaml: file too large
exit 1
$ wc -c < repositories.yaml
0
```

`pkg/repo/v1/repo.go` line 124 at `53dfa52` (the same in v4.3.0) is `return os.WriteFile(path, data, perm)`. `helm repo add` calls the same function; I only ran `repo remove`. In the same package, `index.go` and `chartrepo.go` already write through `fileutil.AtomicWriteFile`, and `File.WriteFile` is the one writer there that does not.

This write was atomic once. #2449 (2017) made it so, #2938 reverted that because of the dependency's licence and said it would need re-implementing, and #7954 (2020) did that for `index.yaml`. The repositories file seems to be the part that was not picked up again.

### What did you expect to happen?

If the repositories file cannot be rewritten, it keeps its previous contents (or holds the new ones), and the error is reported.

### How can we reproduce it (as minimally and precisely as possible)?

1. In an empty directory, create `repositories.yaml`:

   ```yaml
   apiVersion: ""
   generated: "0001-01-01T00:00:00Z"
   repositories:
   - name: a
     url: https://a.example.invalid/charts
   - name: b
     url: https://b.example.invalid/charts
   ```

2. `( ulimit -f 0; helm repo remove b --repository-config repositories.yaml --repository-cache cache ); echo "exit $?"` prints `Error: write repositories.yaml: file too large`, exit 1.
3. `wc -c < repositories.yaml` prints `0` (it was 163).

`ulimit -f 0` stands in for a write that fails after the open. I also killed the process before each of its file operations: killed after the truncating open of `repositories.yaml` and before its write, the file is empty (reproduced twice).

One possible direction, not tried: write through `fileutil.AtomicWriteFile`, as `index.go` does. It renames a temporary file over the target, so a `repositories.yaml` that is a symlink would be replaced by a regular file unless the link is resolved first.

Not tested: a real full disk (`ENOSPC`; `ulimit -f` gives `EFBIG`), power loss, torn writes, Windows, Helm 3.

Disclosure: I found this with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and wrote this report with the help of an AI assistant (Claude), checking it against the runs. If you would rather not have tool-assisted reports here, say so and I will stop.

### Helm version

<details>

```console
$ helm version
version.BuildInfo{Version:"v4.3.0", GitCommit:"bec5b06ed841fe5269972d864d5177944fd5970f", GitTreeState:"clean", GoVersion:"go1.27.1", KubeClientVersion:"v1.37"}
```
</details>

### Kubernetes version

Not applicable: `helm repo remove` does not contact a cluster.
