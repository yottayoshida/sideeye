#!/bin/sh
# Plain run: wp-cli's `config set` on a site's wp-config.php.
. /ap/env.sh
set -u
mkdir -p /lab/wp
cat > /lab/wp/wp-config.php <<'P'
<?php
define( 'DB_NAME', 'household' );
define( 'DB_USER', 'wpuser' );
define( 'DB_PASSWORD', 'old-secret' );
define( 'DB_HOST', 'localhost' );
define( 'AUTH_KEY', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' );
$table_prefix = 'wp_';
if ( ! defined( 'ABSPATH' ) ) { define( 'ABSPATH', __DIR__ . '/' ); }
require_once ABSPATH . 'wp-settings.php';
P
sha256sum /lab/wp/wp-config.php
wp config set DB_PASSWORD new-secret --path=/lab/wp --allow-root </dev/null; echo "rc=$?"
sha256sum /lab/wp/wp-config.php; grep DB_PASSWORD /lab/wp/wp-config.php; ls -la /lab/wp
