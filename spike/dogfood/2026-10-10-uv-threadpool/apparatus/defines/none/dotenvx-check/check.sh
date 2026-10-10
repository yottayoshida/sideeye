#!/bin/sh
# .env and .env.keys are scratch: every encrypt makes a new key pair and fresh ciphertext. This judges
# them through dotenvx: both values come back as they were, whether .env is still plaintext or
# encrypted with the key in .env.keys.
cd "$SIDEEYE_STATE_DIR" || exit 1
a=$(dotenvx get DB_PASSWORD -f .env 2>/tmp/dx.err); b=$(dotenvx get API_TOKEN_PLACEHOLDER -f .env 2>>/tmp/dx.err)
[ "$a" = "hunter2-not-a-real-secret" ] && [ "$b" = "plaintext-value-one" ] && exit 0
echo "dotenvx reads '$a' / '$b': $(head -1 /tmp/dx.err | cut -c1-100)"; exit 1
