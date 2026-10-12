<!-- Draft for ansible/ansible, 2026-10-12. Filed 2026-10-12 as ansible/ansible#87678 without the Configuration and OS / Environment sections,
closed by ansibot for them, and filed again as ansible/ansible#87679 with them: this text, approved
verbatim by the owner (this comment excluded). Contribution policy read: .github/CONTRIBUTING.md and
the community AI policy (ansible-documentation docs/docsite/rst/community/ai_policy.rst), 2026-10-12
— AI-assisted issues are allowed with the author fully accountable and the assistance disclosed
in a short preamble ("Assisted-by:"). Template: bug_report.yml (component ansible-vault).
Title: ansible-vault encrypt loses both the plaintext and the vault if it is killed mid-write -->

Assisted-by: Claude (Anthropic) — the measurement and this text were prepared with it; I have checked both and am responsible for them.

### Summary

`ansible-vault encrypt <file>` shreds and removes the plaintext file before it creates the vault file. If the process is killed between those two steps, the user is left with neither: the plaintext is overwritten with random bytes (or gone), and the encrypted version was never written.

### Issue Type

Bug Report

### Component Name

ansible-vault

### Ansible Version

```console
$ ansible-vault --version
ansible-vault [core 2.21.5]
```

ansible-core 2.21.5 from PyPI, Python 3.13, Debian trixie, aarch64. The same code is on `devel` as of 2026-10-12.

### Configuration

```console
$ ansible-config dump --only-changed
CONFIG_FILE() = None

GALAXY_SERVERS:
```

No `ansible.cfg`; every setting is the default.

### OS / Environment

Debian GNU/Linux 13 (trixie), aarch64, in a Docker container. Python 3.13.5; ansible-core 2.21.5 installed with pip into a virtual environment.

### What happens

`VaultEditor.encrypt_file` reads the plaintext and calls `self.write_data(b_ciphertext, output_file or filename)` (`lib/ansible/parsing/vault/__init__.py`). `write_data` defaults to `shred=True`, so when the target file exists it first calls `self._shred_file(thefile)` — `shred` (coreutils) overwrites the file in place, then the file is removed — and only afterwards creates the file again with `O_CREAT | O_EXCL` and writes the ciphertext.

The plaintext and the ciphertext both exist only in the process's memory from the shred until the write. A failure raised in that window is reported; a killed process (Ctrl-C at the wrong moment, a CI job cancelled, an OOM kill, a reboot) leaves the file shredded, absent, or empty.

ansible/ansible#81455 met the same ordering through a different road — a directory the user cannot write — and was fixed by checking the directory before shredding. That check does not cover an interruption.

### Steps to Reproduce

The window is between the `shred` child's writes and the `write` of the vault; `strace -f` shows it:

```
openat(AT_FDCWD, "/s/av/secrets.yml", O_RDONLY|O_CLOEXEC) = 3          # ansible reads the plaintext
execve("/usr/bin/shred", ["shred", "/s/av/secrets.yml"], ...)          # child process
openat(AT_FDCWD, "/s/av/secrets.yml", O_WRONLY|O_NOCTTY) = 3            # shred overwrites it in place
write(3, "@[\212\243..."..., 217) = 217
...
```

followed by the removal of the file and the creation and write of the vault. Killing `ansible-vault` (or its `shred` child) anywhere after the first overwrite and before the vault's `write` reproduces it.

### Expected Results

After an interruption the file holds either the original plaintext or the complete vault.

### Actual Results

Measured with a 217-byte plaintext `secrets.yml`, killing the process between each pair of its file operations: 15 of 18 states held neither the plaintext nor the vault. The earliest, examined byte by byte, is after `shred`'s first overwrite: `secrets.yml` is 217 bytes of random data. The other 14 come later in the same sequence (the remaining overwrites, the removal, the re-creation, the write) and were counted, not examined one by one. A completed run leaves the 1,197-byte vault. The earliest state was reproduced twice by replaying it. There is no recovery: the plaintext bytes exist nowhere on disk, by design of the shred.

### Why it may be worth fixing

Encrypting a secrets file in place is commonly done right before committing it, so the plaintext is usually not in version control yet; it may be the only copy. Two ways to close it, in increasing order of cost, and I have no stake in which:

1. Write the vault to a temporary file in the same directory, rename it over the plaintext, and shred only what is left after that (a shred after the rename can no longer reach the original blocks, so this trades some of the shred's purpose for safety).
2. Keep the shred first, but write the vault to a temporary file before shredding, so that an interruption leaves the vault beside the shredded original. This keeps the shred's intent and leaves the user one `mv` from a working state.

### Disclosure

Found with Sideeye (https://github.com/yottayoshida/sideeye), a personal open-source project with no commercial interest, which runs a command, kills it between each pair of its file operations, and checks what is left on disk. If you would rather not have tool-generated reports here, say so and I will stop.

### Not claimed

Power loss, torn writes and concurrent processes were not measured. Only `encrypt` on a single file was measured; `rekey`, `edit` and `decrypt` go through the same `write_data` with different `shred` arguments and were not.
