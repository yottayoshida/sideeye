set -eu
rm -rf /s/wp /s/wp-in && mkdir -p /s/wp /s/wp-in
cat > /s/wp/wp-config.php <<'P'
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
