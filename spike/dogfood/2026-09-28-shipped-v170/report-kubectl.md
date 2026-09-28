Title: `kubectl config` empties the kubeconfig when the write fails or the process is killed mid-write

**What happened**:

A `kubectl config` command that is killed, or whose write fails, between opening the kubeconfig and writing it leaves the file at 0 bytes. The previous contents — cluster endpoints, contexts, credentials — are gone. `ulimit -f 0` reproduces it without a crash:

```
$ wc -c < config
355
$ ( ulimit -f 0; kubectl config use-context b --kubeconfig ./config )
error: write ./config: file too large
$ wc -c < config
0
```

`clientcmd.WriteToFile` (`staging/src/k8s.io/client-go/tools/clientcmd/loader.go`, line 466 on `master`) calls `os.WriteFile(filename, content, 0600)`, which opens the file with `O_TRUNC` and writes afterwards. Between the two the old kubeconfig is gone from disk while the new one is still in memory, so a kill, a full disk or a failed write in that window leaves an empty file. The `.lock` file guards against concurrent writers; it does not help here.

**What you expected to happen**:

The kubeconfig holds either its old contents or its new ones, whatever happens to the process.

**How to reproduce it (as minimally and precisely as possible)**:

With any kubeconfig that has two contexts:

```
cp ~/.kube/config ./config
( ulimit -f 0; kubectl config use-context <other-context> --kubeconfig ./config )
wc -c < ./config   # 0
```

Killing the process instead gives the same result. I also checked it by killing kubectl before each state-changing syscall. `strace` shows four: `openat("config.lock", O_RDONLY|O_CREAT|O_EXCL)`, `openat("config", O_WRONLY|O_CREAT|O_TRUNC)`, one `write` of 339 bytes, and `unlinkat("config.lock")`. Killed after the `openat` and before the `write` — crash point 3 of 4 — the kubeconfig is empty and `config.lock` is left behind. That was reproduced twice from the saved case.

**Anything else we need to know?**:

Most files a command rewrites in place can be recovered from version control. A kubeconfig usually cannot, and it often holds credentials that took a login flow to get.

The usual fix would be to write to a temporary file in the same directory, `fsync` it, and `rename` it over the original (keeping the `0600` mode). If there is a reason not to do that, a line in the docs would help.

**Environment**:
- Kubernetes client and server versions (use `kubectl version`): client v1.37.1 (the release binary from dl.k8s.io, linux/arm64); no server needed
- Cloud provider or hardware configuration: none, local Docker container
- OS (e.g: `cat /etc/os-release`): Debian 13 (trixie)

<details><summary>How this was found</summary>

With [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, with no commercial interest. It kills the process before each state-changing operation and checks what is left. The checker used here (`kubectl config view` must still read both contexts) was first checked against deliberately corrupted state, so a check that could not fail did not produce this. This report was written in part with the assistance of generative AI, from that tool's output, and I checked it. Not measured: power loss, torn writes, concurrent processes.
</details>
