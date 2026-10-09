#!/bin/sh
# Judged through dotenvx itself (the version on PATH): every value reads back, from whichever files
# hold it, with whatever key .env.keys holds. A file still in plaintext reads back too.
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
expect .env DB_PASSWORD hunter2-not-a-real-secret
expect .env API_TOKEN_PLACEHOLDER plaintext-value-one
expect .env.production PROD_DB_PASSWORD prod-value-two-not-real
expect .env.production PROD_FLAG prod-value-three
exit $bad
