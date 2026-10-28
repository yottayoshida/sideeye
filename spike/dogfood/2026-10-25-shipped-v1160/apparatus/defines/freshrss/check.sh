#!/bin/sh
# After a crash anywhere inside `reconfigure.php`, FreshRSS still loads its instance configuration:
# data/config.php returns an array whose salt is the install's (a lost salt invalidates every stored
# password), and FreshRSS's own CLI still lists the instance's user from it. Not cli/health.php: it
# checks the web API over HTTP, which the box has none of.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(freshrss): $*"; exit 1; }
[ -f "$d/config.php" ] || fail "config.php is missing"
salt=$(php -r '$c = @include $argv[1]; if (!is_array($c)) exit(3); echo $c["salt"] ?? "";' "$d/config.php" 2>&1) || fail "config.php does not return an array (php exited $?): $(echo "$salt" | cut -c1-200)"
[ "$salt" = "$(cat /s/freshrssaux/salt)" ] || fail "the instance salt changed or is gone: [$salt]"
out=$(DATA_PATH="$d" php /opt/freshrss/cli/list-users.php 2>&1) || fail "list-users.php exited $?: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
printf '%s' "$out" | grep -q alice || fail "list-users.php does not list alice: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
exit 0
