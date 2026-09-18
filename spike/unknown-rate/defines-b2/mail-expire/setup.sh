#!/bin/sh
set -eu
cat > "$TOY_STATE/inbox" <<'EOF'
From alice@example.org Sat Jan  4 10:00:00 2020
From: alice@example.org
To: bob@example.org
Subject: old
Date: Sat, 04 Jan 2020 10:00:00 +0000

old body

From carol@example.org Wed Jan  1 10:00:00 2031
From: carol@example.org
To: bob@example.org
Subject: fresh
Date: Wed, 01 Jan 2031 10:00:00 +0000

fresh body

EOF
