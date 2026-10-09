Title: dotenvx encrypt leaves .env empty if it is killed while writing it

`dotenvx encrypt` writes `.env.keys`, then rewrites `.env` with `fs.promises.writeFile` (`writeFileX` in `src/lib/helpers/fsx.js`, the same on `main` at da2acf75cb), which empties the file before it writes. If the process is killed in between, `.env` is left at 0 bytes and its values are gone; `.env` is usually not in version control. `set`, `decrypt` and `del` use the same write.

To reproduce (dotenvx 2.32.4, Debian 13 arm64):

```
printf 'DB_PASSWORD=hunter2\n' > .env
strace -f -qq -P "$PWD/.env" -e inject=write,pwrite64:signal=KILL dotenvx encrypt -f .env
ls -la
```

`.env` goes from 20 bytes to 0, while `.env.keys` is written.

**Expected:** `.env` holds its old content or its new content.

Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest; say if you would rather not have such reports. Not measured: power loss.
