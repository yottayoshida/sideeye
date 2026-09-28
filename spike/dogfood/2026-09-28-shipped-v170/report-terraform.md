Title: `terraform fmt` leaves a `.tf` file empty when its write fails or the process is killed before the write

### Terraform Version

```
Terraform v1.16.4
on linux_arm64
```

### Terraform Configuration Files

```hcl
variable "a" {
default="x"
  type =    string
}

locals {
    b = var.a
c =   "y"
}
```

### Debug Output

```
$ ( ulimit -f 0; TF_LOG=trace terraform fmt -no-color ); echo "exit $?"
...
[INFO]  CLI command args: []string{"fmt", "-no-color"}
[TRACE] terraform fmt: looking for files in .
[TRACE] terraform fmt: Formatting main.tf
main.tf

Error: Failed to write main.tf

exit 2
$ wc -c < main.tf
0
```

### Expected Behavior

If `terraform fmt` cannot finish rewriting `main.tf`, the file still holds its original contents (or the formatted ones), and the command reports the error.

### Actual Behavior

The error is reported, but `main.tf` is left at 0 bytes and its original 84 bytes are gone. The same happens when the process is killed at that point.

`internal/command/fmt.go` line 191 (at `db4eef4`) writes the result with `os.WriteFile(path, result, 0644)`, which opens the file with `O_TRUNC` and then writes. Between the two the file on disk is empty, so a failed write (a full disk, a quota, `ulimit -f`) or a kill in that window leaves it empty.

### Steps to Reproduce

1. Put the configuration above in `main.tf` in an empty directory.
2. `( ulimit -f 0; terraform fmt ); echo "exit $?"` — prints `Error: Failed to write main.tf`, exit 2.
3. `wc -c < main.tf` — `0`.

### Additional Context

`ulimit -f 0` stands in for a write that fails after the open. I also killed the process before each file operation: killed after the truncating `openat` of `main.tf` and before its `write`, the file is empty (reproduced twice). `.tf` files are usually in version control, but `terraform fmt` is run on working trees, where uncommitted edits in the file are lost with it.

Not tested: a real full disk (`ENOSPC`; `ulimit -f` gives `EFBIG`), power loss, torn writes.

### References

_No response_

### Generative AI / LLM assisted development?

Not for the configuration. The report was written with the help of an AI assistant (Claude) from the output of [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and I checked it against the runs.
