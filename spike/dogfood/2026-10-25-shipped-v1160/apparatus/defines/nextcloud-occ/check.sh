#!/bin/sh
# After a crash anywhere in `occ config:system:set`, the instance is still the installed one:
# config.php parses and still holds the secret, password salt and instance id it was installed with
# (losing them invalidates every stored credential and session), and `occ status` reports it installed.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(nextcloud-occ): $*"; exit 1; }
[ -f "$d/config.php" ] || fail "config.php is missing"
got=$(php -r 'include $argv[1]; if (!isset($CONFIG) || !is_array($CONFIG)) exit(3); echo $CONFIG["secret"] ?? "", "\n", $CONFIG["passwordsalt"] ?? "", "\n", $CONFIG["instanceid"] ?? "", "\n";' "$d/config.php" 2>&1) \
    || fail "config.php does not load as a configuration ($?): $(printf '%s' "$got" | tail -c 200)"
[ "$got" = "$(cat /s/nc-expected.txt)" ] || fail "config.php lost the secret, password salt or instance id it was installed with"
st=$(NEXTCLOUD_CONFIG_DIR="$d/" php /opt/nextcloud/occ status --output=json 2>&1) || fail "occ status exited $?: $(printf '%s' "$st" | tail -c 200)"
printf '%s' "$st" | grep -q '"installed":true' || fail "occ status does not report the instance installed: $(printf '%s' "$st" | tail -c 200)"
exit 0
