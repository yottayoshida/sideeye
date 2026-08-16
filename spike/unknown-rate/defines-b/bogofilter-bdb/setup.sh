#!/bin/sh
set -eu
cat > "$TOY_STATE/ham.eml" <<'EOF'
From: ada@example.org
Subject: meeting notes

The quarterly numbers look steady and the calendar invite is attached.
EOF
cat > "$TOY_STATE/spam.eml" <<'EOF'
From: winner@example.net
Subject: you won a prize

Claim your free prize now, limited offer, click quickly for cash rewards.
EOF
bogofilter-bdb -n -d "$TOY_STATE" -I "$TOY_STATE/ham.eml"
