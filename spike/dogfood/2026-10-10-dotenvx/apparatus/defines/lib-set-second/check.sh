#!/bin/sh
# Judged through dotenvx itself (the version on PATH): .env's values read back with whatever .env.keys
# holds, and .env.production keeps its value and holds the new one or none.
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
expect .env DB_PASSWORD hunter2-not-a-real-secret
expect .env API_TOKEN_PLACEHOLDER plaintext-value-one
expect .env.production PROD_FLAG prod-value-three
expect .env.production PROD_DB_PASSWORD prod-value-two-not-real '<absent>'
exit $bad
