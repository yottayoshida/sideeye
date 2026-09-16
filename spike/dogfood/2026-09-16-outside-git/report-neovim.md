Title: ShaDa: vim_rename() removes main.shada before the rename; a kill in between loses history silently

### Problem

**Minor; won't-fix is a fine outcome.**

`shada_write_file()` writes the complete file to `main.shada.tmp.a`, then `vim_rename()` runs `os_remove(to)` before `os_rename()` (`src/nvim/fileio.c`, unchanged on master). Killed between the two, Nvim leaves no `main.shada`: the next session has no command history or registers and says nothing, and `main.shada.tmp.a` is never read again. #4547 describes write-then-rename as atomic; the removal undoes that.

### Steps to reproduce

```sh
printf 'call histadd("cmd", "echo first")\nwshada!\nqa!\n' > first.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > second.vim
nvim --headless -n -u NONE -i main.shada -S first.vim
strace -f -o /dev/null -e inject=/^rename:signal=KILL:when=1 \
  nvim --headless -n -u NONE -i main.shada -S second.vim
ls -l main.shada*
nvim --headless -n -u NONE -i main.shada \
  +'call writefile([string(histnr("cmd"))], "/dev/stdout")' +'qa!'
```

Only `main.shada.tmp.a` (134 bytes) remains; prints `-1`. Without `strace`: `main.shada`, prints `2`.

### Expected behavior

`main.shada` keeps the old or new contents. E.g. skip the removal where `rename` replaces the target.

### Nvim version (nvim -v)

v0.12.5 (release tarball); 0.10.4 (Debian) too

### Vim (not Nvim) behaves the same?

Not tested

### Operating system/version

Debian 13, aarch64

### Terminal name/version

none (headless)

### $TERM environment variable

n/a

### Installation

Release tarball

<details><summary>How this was found</summary>

[sideeye](https://github.com/yottayoshida/sideeye), my non-commercial crash-consistency checker, kills the process before each syscall: 2 of 12 kill points fail. Drafted with AI, reviewed by @yottayoshida. Say so if you'd rather not get such reports.

</details>
