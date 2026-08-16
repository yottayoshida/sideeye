#!/bin/sh
set -eu
cat > "$TOY_STATE/aliases" <<'EOF'
alias ada Ada Lovelace <ada@example.org>
alias grace Grace Hopper <grace@example.org>
EOF
