set -eu
# 2026-09-06 userview-2's bean-format define; the binary is PR #1054 at cc591f7fcf.
rm -rf /s/bc && mkdir -p /s/bc
printf '2026-01-01 open Assets:Cash\n2026-01-01 open Expenses:Food\n2026-01-02 * "lunch"\n  Expenses:Food   10.00 JPY\n  Assets:Cash\n2026-01-03 * "coffee"\n  Expenses:Food    3.50 JPY\n  Assets:Cash\n' > /s/bc/l.beancount
