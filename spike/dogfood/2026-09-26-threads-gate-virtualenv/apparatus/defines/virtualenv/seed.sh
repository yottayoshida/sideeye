# The 2026-09-16 define (spike/dogfood/2026-09-16-userview-3/apparatus/run-r3.sh, which
# run-v18.sh took verbatim): an empty state with one environment, v1, already made. Two
# changes, both because this runs from entry.sh's seed rather than once per run:
# - virtualenv's app-data cache (outside --state, which `--twice` does not put back) is
#   removed before v1 is made, so every seed leaves it in the same filled state;
# - /usr/bin/virtualenv by path: this box's PATH starts with /opt/py/bin, a venv that
#   carries no virtualenv of its own but whose python3 is not Debian's.
set -eu
rm -rf /s/venv /root/.local/share/virtualenv
mkdir -p /s/venv
/usr/bin/virtualenv -q --no-download /s/venv/v1 > /dev/null 2>&1
