# Four fixes upstream, walked through

Four tools where Sideeye found a moment in which a killed process left a user's file empty or gone, what their projects changed, and what running Sideeye again against the fix showed. They are four of the reports [docs/found.md](found.md) lists as fixed upstream and re-measured; that page keeps the full list and each report's state. Release status below is as checked on 2026-10-10.

## The moment between two calls

When a program saves a file, it makes a few system calls in a row: open the file (often truncating it), write the new bytes, perhaps rename a temporary file over the old one. If the process is killed between two of those calls — `kill -9`, the OOM killer, a CI job hitting its timeout — whatever is on disk at that moment is what the user gets back.

Sideeye kills the operation before each state-changing call, one crash world per call, and brings back the earliest world where the declared invariant broke, as a case that can be replayed. Its crash model is the process dying, not the machine losing power: what the process wrote before it died is kept.

## dotenvx: `encrypt` left `.env` empty

[dotenvx](https://github.com/dotenvx/dotenvx) encrypts a project's `.env` in place and keeps the private key in `.env.keys`. In 2.32.4, `dotenvx encrypt` rewrote `.env` with `fs.promises.writeFile`, which truncates the file first and writes second. Killed between the two, `.env` was left at 0 bytes. Since `.env` is usually not committed, the plaintext values were gone unless a copy lived somewhere else.

The same shape on `.env.keys` is worse. If that file held the only copy of the private key, emptying it means the encrypted `.env` that was committed can no longer be decrypted.

The report was [dotenvx#1012](https://github.com/dotenvx/dotenvx/issues/1012). The maintainer merged [a fix](https://github.com/dotenvx/dotenvx/pull/1014) about seven hours later and released it as 2.34.2 the same day: writes through its file helper now go through `write-file-atomic`, which writes a temporary file, syncs it and renames it over the original. Re-run against 2.34.2, every form of the write that had failed (in `encrypt`, `set`, `decrypt` and `del`) passed. The same re-run found writes the fix did not reach, `dotenvx protect` among them, reported as [dotenvx#1018](https://github.com/dotenvx/dotenvx/issues/1018).

Both runs set `UV_THREADPOOL_SIZE=1`. By default Node's thread pool does the writing on a second thread, and Sideeye declines to judge a target that writes from more than one. Record: [`spike/dogfood/2026-10-10-dotenvx/`](../spike/dogfood/2026-10-10-dotenvx/RESULTS.md).

## Neovim: `:wshada` removed the old file before renaming the new one

Neovim keeps command history, registers and marks in a ShaDa file. To save it, Neovim 0.12.5's `:wshada` wrote the new contents to `main.shada.tmp.a`, removed `main.shada`, then renamed the temporary file into place. Killed between the remove and the rename, there was no `main.shada` at all. The next start came up without the command history and registers the test had saved, and said nothing. The new contents were still on disk under the temporary name, but Neovim never reads that name. In 0.10.4, also measured, the contents were written after the rename, so a kill could leave nothing at all.

The report was [neovim#41940](https://github.com/neovim/neovim/issues/41940). Another user then hit the same gap without any kill: several Neovim instances exiting at once raced through it, with E137 and E136 errors and stray temporary files.

The fix, [PR #42152](https://github.com/neovim/neovim/pull/42152), tries the rename first and falls back to remove-then-rename only when the rename fails. Re-run against a nightly build (v0.13.0-dev-1824), all 11 crash worlds passed, where 0.12.5 failed 2 of 13 in the same container. As of 2026-10-10 the fix is on master and not in a release: 0.12.6 does not carry it. Records: [`spike/dogfood/2026-09-16-outside-git/`](../spike/dogfood/2026-09-16-outside-git/RESULTS.md), [`spike/dogfood/2026-10-09-followups/`](../spike/dogfood/2026-10-09-followups/RESULTS.md).

## RuboCop: an interrupted `rubocop -a` left the file at 0 bytes

`rubocop -a` rewrote each corrected file with `File.write`, which opens the file with truncation and then writes. Killed in between, the Ruby file being fixed was left empty, along with any edits not yet committed. A write that fails does the same without a kill; `ulimit -f 0` reproduces it. Measured on 1.39.0, Debian's package; standardrb inherits the same write.

The report was [rubocop#15720](https://github.com/rubocop/rubocop/issues/15720), and [PR #15721](https://github.com/rubocop/rubocop/pull/15721) was merged about eleven hours later. It writes to a temporary file in the same directory and renames it over the original, keeping the original's mode and resolving a symlink first. It does not sync the file, which the pull request says is out of its scope.

Re-run at the merged commit (b39e7f467), all 9 crash worlds passed, where its parent failed 2 of 5. As of 2026-10-10 the fix is not in a release. Record: [`spike/dogfood/2026-10-02-gate-cleared-twelve/`](../spike/dogfood/2026-10-02-gate-cleared-twelve/RESULTS.md).

## ImageMagick: the first fix made it worse

`mogrify` edits images in place. Version 7.1.1-43 renamed `img1.png` to `img1.png~`, then created a new `img1.png` and wrote into it. Killed in between, nothing was left at the original name. The old image survived as `img1.png~`, so this one was mild: a `mv` puts it back.

The first patch after [the report](https://github.com/ImageMagick/ImageMagick/issues/8939) hard-linked the backup to the original name and then truncated it. Both names now pointed at one file, so the write emptied the backup too. Running the patch against a full disk, with no kill at all, left both names at 204,800 bytes and neither one an image. That went back on the issue, and the maintainer reverted the patch the same hour.

The next version writes a temporary file under a new name and renames it into place. Re-run at that commit (960adadd), all 4 crash worlds passed, where 7.1.1-43 failed 2 of 5, and the full disk left the original untouched. 7.1.2-32 carries the fix, along with a later change that opens the temporary file exclusively; that release was not re-measured. Records: [`spike/dogfood/2026-09-05-userview/`](../spike/dogfood/2026-09-05-userview/RESULTS.md), [`spike/dogfood/2026-09-06-imagemagick-refix/`](../spike/dogfood/2026-09-06-imagemagick-refix/RESULTS.md), [`spike/dogfood/2026-09-06-imagemagick-patch3/`](../spike/dogfood/2026-09-06-imagemagick-patch3/RESULTS.md).

## Three windows, one fix

All four bugs were a moment where the file the user cares about did not exist, or existed empty. On their normal path, all four fixes end the same way: the new bytes go to a temporary name first, and a single rename puts them at the real name. Two keep an older path for when that fails: Neovim falls back to remove-then-rename, and RuboCop writes in place when it is refused the temporary file.

| Tool and version measured | What sat between two calls | What the fix does |
| --- | --- | --- |
| dotenvx 2.32.4 | truncate `.env`, then write it | temporary file, sync, rename |
| Neovim 0.12.5 | remove `main.shada`, then rename the new one in | rename first; remove only if that fails |
| RuboCop 1.39.0 | truncate the file, then write it | temporary file in the same directory, rename |
| ImageMagick 7.1.1-43 | rename the original away, then create and write | temporary file, rename |

A rename onto an existing name is a single step on POSIX file systems: a reader sees the old file or the new one, never neither. None of these needed a power cut to show up: a process killed at the wrong moment was enough. To run Sideeye on a tool of your own, start at the [README](../README.md).
