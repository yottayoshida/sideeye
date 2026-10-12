<!-- Draft for rclone/rclone, 2026-10-12. Filed 2026-10-12 as rclone/rclone#10076: the owner approved the free-form draft, it was
arranged into the sections .github/ISSUE_TEMPLATE/bug.yml requires, and shortened at the owner's
request; what follows is the text filed (this comment excluded). Contribution policy read: CONTRIBUTING.md
"AI-assisted contributions", 2026-10-12 — about pull requests; the contributor is responsible and
must understand and verify the contribution. Title: rclone.conf disappears if rclone is killed
while saving the config -->

### Before you start

- [X] I have searched the [forum](https://forum.rclone.org/) and the existing issues for this problem.
- [X] I have tested with the latest beta or stable release and can still reproduce the problem.
- [X] This is a reproducible bug, not a usage question (questions belong on the forum).

### Associated forum post URL

_No response_

### What is the problem you are having with rclone?

**No data is lost by this**, but if rclone is killed while saving its config, `rclone.conf` disappears: rclone then reports `Config file "…/rclone.conf" not found - using defaults` and lists no remotes until the user renames a backup file back by hand.

`(*Storage).Save` (`fs/config/configfile/configfile.go`, `master` as of 2026-10-12) writes and `fsync`s a temporary file, then makes two renames:

```
renameat(AT_FDCWD, "/s/rclone/rclone.conf", AT_FDCWD, "/s/rclone/rclone.conf.old3992793341") = 0
renameat(AT_FDCWD, "/s/rclone/rclone.conf249033223", AT_FDCWD, "/s/rclone/rclone.conf") = 0
```

Between them there is no `rclone.conf`. Killed there (measured by killing rclone between each pair of its file operations), the directory holds `rclone.conf.old<n>` (the old 404 bytes) and `rclone.conf<n>` (the new 405), and:

- `rclone listremotes` lists nothing;
- `rclone lsd backup:` fails with `didn't find section in config file ("backup")`;
- running the same `config update` again exits 2.

Recovery is `mv rclone.conf.old<n> rclone.conf`, once the user knows to look.

### rclone version

```
rclone v1.75.2
- os/version: debian 13.7 (64 bit)
- os/kernel: 6.12.76-linuxkit (aarch64)
- os/type: linux
- os/arch: arm64 (ARMv8 compatible)
- go/version: go1.26.9
- go/linking: static
- go/tags: none
```

### Operating system

Linux

### Which cloud storage system are you using?

None in particular: the problem is in saving the config file (the config holds local, S3, SFTP and crypt remotes).

### Output of `rclone config redacted`

```ini
[backup]
type = local

[crypt]
type = crypt
remote = s3prod:archive-bucket/vault
filename_encryption = standard
directory_name_encryption = true

[photos]
type = sftp
host = XXX
user = XXX
key_file = ~/.ssh/nas_ed25519
shell_type = unix

[s3prod]
type = s3
provider = AWS
access_key_id = XXX
secret_access_key = XXX
region = us-east-1
acl = private
```

### The command you were trying to run

```shell
rclone config update s3prod region eu-west-1 --non-interactive
```

### A log from the command with the `-vv` flag

An uninterrupted run completes normally; the problem needs a kill between the two renames.

```shell
DEBUG : Using config file from "/s/rclone/rclone.conf"
DEBUG : Saving config "region" in section "s3prod" of the config file
DEBUG : s3prod: config in: state="", result=""
DEBUG : s3prod: config out: out=<nil>, err=<nil>
DEBUG : rclone: Version "v1.75.2" finishing with parameters ["rclone" "config" "update" "s3prod" "region" "eu-west-1" "--non-interactive" "-vv"]
```

### Anything else?

A possible fix: rename the new file directly over `rclone.conf` (atomic on POSIX) and keep the backup as a copy or hard link made beforehand, so the name never goes missing. I have not checked whether the move-aside step exists for a platform where renaming over a file fails.

Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool (no commercial interest) that kills a command between its file operations and checks what is left. Prepared with an AI assistant (Claude) and checked by me; if you would rather not have tool-generated reports here, say so and I will stop. Power loss and concurrent rclone processes were not measured.
