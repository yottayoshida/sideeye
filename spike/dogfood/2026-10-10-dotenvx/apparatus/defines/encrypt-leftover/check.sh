#!/bin/sh
# Judged through dotenvx itself (the version on PATH): every value reads back, from whichever files
# hold it, with whatever key .env.keys holds; and nothing `git add -A` would stage holds a private key.
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
no_private_key_staged
expect .env DB_PASSWORD hunter2-not-a-real-secret
expect .env API_TOKEN_PLACEHOLDER plaintext-value-one
exit $bad
