Not posted (2026-10-10): picked against in the value reading — see RESULTS.md, "Reported upstream".

Title: A killed dotenvx encrypt can leave the private keys in .env.keys.<number>, which a .env.keys ignore line misses

Since 2.34.2, `.env.keys` is written to `.env.keys.<number>` and renamed. `write-file-atomic` does not remove that file on SIGKILL, so a kill before the rename leaves it, with every key `.env.keys` held. A `.gitignore` line `.env.keys` (`dotenvx gitignore --pattern .env.keys`, as `dotenvx help` shows) does not match it, and `git add -A` stages it. `.env*` and `protect` cover it.

To reproduce (2.34.2, Debian 13 arm64):

```
git init -q demo && cd demo
printf 'DB_PASSWORD=hunter2\n' > .env; printf 'PROD=x\n' > .env.production
printf '.env.keys\n.env.production\n' > .gitignore
dotenvx encrypt -f .env && git add -A && git commit -qm init
strace -f -qq -o /dev/null -e inject=renameat,renameat2:signal=KILL dotenvx encrypt -f .env.production
git add -A && git status --short
```

`git status` shows `A  .env.keys.<number>`; given it as `-fk`, `dotenvx get DB_PASSWORD -f .env` prints `hunter2`. A later `encrypt` leaves it in place, and `decrypt` leaves `.env.<number>` in plaintext the same way.

**Expected:** no copy of the keys that a `.env.keys` ignore line misses.

Found with Sideeye, as #1012.
