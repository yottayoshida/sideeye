Title: Two dotenvx encrypt runs at once with a shared .env.keys leave one env file undecryptable

When keys go to `.env.keys` (no OS secret store, as on CI and in containers, or `--no-native`), `encrypt` reads that file, adds the new key and writes the whole file back. Two runs at once on different env files with one `-fk` (the single root `.env.keys` of #703) each write back what they read, so the later write drops the other run's key, after that run has already replaced its file's plaintext with ciphertext under that key. Two `set` at once on one `.env` lose a value the same way.

To reproduce (2.34.2, Debian 13 arm64):

```
mkdir -p demo/apps/a demo/apps/b && cd demo
printf 'A_SECRET=a\n' > apps/a/.env; printf 'B_SECRET=b\n' > apps/b/.env
dotenvx encrypt -fk .env.keys -f apps/a/.env & dotenvx encrypt -fk .env.keys -f apps/b/.env & wait
dotenvx get A_SECRET -fk .env.keys -f apps/a/.env; dotenvx get B_SECRET -fk .env.keys -f apps/b/.env
```

One of the two prints `encrypted:...` with `[DECRYPTION_FAILED]`, and `.env.keys` holds one key: 20 runs out of 20, and the same on 2.32.4. Run one after the other, both decrypt.

**Expected:** both files decrypt, or the second run fails before it touches its file.

Found alongside the Sideeye runs for #1012; Sideeye does not test concurrent runs, so this one is a plain script.
