#!/bin/sh
mkdir -p /work/st2/bc
cat > /work/st2/bc/l.beancount <<'EOB'
2026-01-01 open Assets:Cash
2026-01-01 open Expenses:Food
2026-01-02 * "lunch"
  Expenses:Food   10.00 JPY
  Assets:Cash
2026-01-03 * "coffee"
  Expenses:Food    3.50 JPY
  Assets:Cash
EOB
