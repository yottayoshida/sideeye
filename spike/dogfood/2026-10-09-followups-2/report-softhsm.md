Title: A crash while softhsm2-util --import rewrites token.object leaves it empty, and the token with every key in it unreadable

With the file backend, `ObjectFile::writeAttributes` truncates an object file and then writes it (`src/lib/object_store/ObjectFile.cpp`, unchanged on `main` at 9ad87341c9). `softhsm2-util --import` rewrites the token's own `token.object` this way. If the process is killed between the truncation and the write, `token.object` is left at 0 bytes, and the token disappears from its slot. The keys already in it are lost with it: their object files are still on disk, but `token.object` held the SO and user PIN blobs SoftHSM unwraps their key from.

**To reproduce** (SoftHSM 2.6.1, Debian 13 arm64):

```
export SOFTHSM2_CONF=$PWD/softhsm2.conf
mkdir tokens
printf 'directories.tokendir = %s/tokens\nobjectstore.backend = file\n' "$PWD" > softhsm2.conf
softhsm2-util --init-token --free --label t --pin 1234 --so-pin 5678
openssl genpkey -algorithm RSA -out k1.pem; openssl genpkey -algorithm RSA -out k2.pem
softhsm2-util --import k1.pem --token t --pin 1234 --label k1 --id 01
tok=$(ls -d tokens/*/)
strace -f -qq -P "$PWD/${tok}token.object" -e inject=write:signal=KILL \
  softhsm2-util --import k2.pem --token t --pin 1234 --label k2 --id 02
ls -l "$tok"; softhsm2-util --show-slots
```

strace shows `ftruncate(3, 0)` on `token.object` and the kill at the write that follows. Afterwards `token.object` is 0 bytes, `--show-slots` lists the slot with an empty label, and `pkcs11-tool --token-label t --login --pin 1234 --list-objects` answers `No slot with token named "t" found`, while k1's object file is still in the directory.

**Expected:** `token.object` holds its old content or its new content.

Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest; say if you would rather not have such reports. Not measured: power loss, the database backend, and which other operations rewrite `token.object`.
