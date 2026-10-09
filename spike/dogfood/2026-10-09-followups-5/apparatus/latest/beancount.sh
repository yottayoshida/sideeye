# beancount/beancount#1051: `bean-format --in-place`, with writes failing (ulimit -f 0) and killed at its first
# write to the ledger. A ledger of two transactions, as the report's ("lunch", "coffee").
mkdir -p /work/bc && cd /work/bc
mk() { printf '2026-01-01 open Assets:Cash\n2026-01-01 open Expenses:Food\n\n2026-09-01 * "lunch"\n  Expenses:Food  12.50 USD\n  Assets:Cash\n\n2026-09-02 * "coffee"\n  Expenses:Food  3.20 USD\n  Assets:Cash\n' > l.beancount; }
mk; wc -c l.beancount
(ulimit -f 0; /opt/py/bin/bean-format --in-place l.beancount); echo "exit $?"
wc -c l.beancount
mk; strace -f -qq -P "$PWD/l.beancount" -e trace=openat,write -e inject=write:signal=KILL /opt/py/bin/bean-format --in-place l.beancount; echo "exit $?"
wc -c l.beancount
