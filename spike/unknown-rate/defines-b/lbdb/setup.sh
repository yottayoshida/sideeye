#!/bin/sh
set -eu
cat > "$TOY_STATE/mail.eml" <<'EOF'
From: Ada Lovelace <ada@example.org>
To: Grace Hopper <grace@example.org>
Subject: hello

A short note.
EOF
: > "$TOY_STATE/m_inmail"
