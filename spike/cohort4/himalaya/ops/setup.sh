#!/bin/sh
# Cohort-4 himalaya define (P1) setup: the maildir store (state root) in
# io-maildir's default nested-fs layout — the root directory is itself the
# INBOX — holding one existing message, plus the account configuration the
# operation reads from outside the root.
#
# Fixture bytes are the accepted probe's, unchanged (spike/cohort4/PROTOCOL.md
# "Probe plans", target 1, and probes/himalaya.txt). The config, HOME and
# XDG directories are ambient created here, outside the snapshot; the
# config's only variable is the store path.
set -eu
P=/tmp/cohort4/himalaya
MSGID='1700000000.#0M0P1.probehost'

rm -rf "$P/store" "$P/home" "$P/xdg"
mkdir -p "$P/store/cur" "$P/store/new" "$P/store/tmp" \
         "$P/store/Archive/cur" "$P/store/Archive/new" "$P/store/Archive/tmp" \
         "$P/home" "$P/xdg"

cat > "$P/store/cur/$MSGID:2,S" <<'EOF'
Return-Path: <probe@example.invalid>
Date: Sat, 01 Mar 2026 09:00:00 +0000
From: Probe Author <probe@example.invalid>
To: Probe Target <target@example.invalid>
Subject: Existing message, fixed bytes
Message-ID: <existing0001@example.invalid>

This is the existing message. Its bytes are part of the freeze.
EOF

cat > "$P/config.toml" <<EOF
[accounts.probe]
default = true
maildir.root = "$P/store"
EOF
