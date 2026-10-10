#!/bin/sh
# The private key is somewhere in the state: the value reads back, through dotenvx or with a key found in
# .env.keys, the stand-in keyring or the stand-in 1Password or Bitwarden.
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
recoverable .env DB_PASSWORD hunter2-not-a-real-secret
exit $bad
