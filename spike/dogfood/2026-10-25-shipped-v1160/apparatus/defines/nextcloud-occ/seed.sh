set -eu
# The configuration Nextcloud 33.0.10's `maintenance:install` wrote in the box (SQLite, admin "admin"),
# plus the settings an administrator adds after installing.
rm -rf /s/ncconf && mkdir -p /s && cp -a /opt/nc-config-proto /s/ncconf
export NEXTCLOUD_CONFIG_DIR=/s/ncconf/
for kv in "overwrite.cli.url https://cloud.internal" "default_phone_region JP" "maintenance_window_start 1" \
          "mail_smtpmode smtp" "mail_smtphost smtp.internal" "mail_from_address cloud" "mail_domain example.com"; do
    set -- $kv; php /opt/nextcloud/occ config:system:set "$1" --value="$2" > /dev/null
done
php -r 'include "/s/ncconf/config.php"; echo $CONFIG["secret"], "\n", $CONFIG["passwordsalt"], "\n", $CONFIG["instanceid"], "\n";' > /s/nc-expected.txt
install -m 755 /ap/defines/nextcloud-occ/check.sh /s/nc-check.sh
