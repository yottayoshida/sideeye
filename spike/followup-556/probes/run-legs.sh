#!/bin/sh
# The two #556 legs, cut verbatim out of spike/acceptance.sh, against four builds.
set -u
echo "image libc: $(ldd --version 2>&1 | head -1)  python: $(python3 --version 2>&1)  arch: $(uname -m)"
echo "legs sha256: $(sha256sum /t/legs556.sh | cut -d' ' -f1)  toy-raw sha256: $(sha256sum /t/out/toy-raw | cut -d' ' -f1)"
for name in main fixed m1 m2; do
  SIDEEYE=/b/$name/sideeye SHIM=/b/$name/libsideeye_shim.so OUT=/t/out
  echo "==================== $name   engine: $("$SIDEEYE" --version 2>&1 | head -1)   shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
  fails=0
  . /t/legs556.sh
  echo "fails=$fails"
done
