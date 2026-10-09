#!/bin/sh
# Every value reads back through dotenvx, and no file `git add -A` would stage holds a key that
# decrypts the committed .env (tried with that file as the keys file).
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
for f in $(git ls-files --others --exclude-standard); do
  got=$(dotenvx get DB_PASSWORD -f .env -fk "$f" 2>/dev/null)
  [ "$got" = hunter2-not-a-real-secret ] && { echo "git would stage $f, and it decrypts the committed .env"; bad=1; }
done
expect .env DB_PASSWORD hunter2-not-a-real-secret
expect .env.production PROD_DB_PASSWORD prod-value-two-not-real
exit $bad
