set -eu
. /ap/defines/firefly/env.sh
# The books, built once per box: migrate, the owner, one correct-database to make the owner's group
# and the OAuth keys (written to the app's storage/, outside the state, and kept for every world),
# a month of transactions (make_data.php), then what correct-database exists to repair (inject.sql).
# Every seed copies that same database file back.
tpl=/s/aux/tpl-ff
cd /opt/firefly
if [ ! -f $tpl/database.sqlite ]; then
    rm -rf /s/ff "$tpl"; mkdir -p /s/ff; : > /s/ff/database.sqlite
    php8.5 artisan migrate --seed --force > /s/aux/ff-migrate.log 2>&1
    php8.5 -r 'require "vendor/autoload.php"; $app = require "bootstrap/app.php"; $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap(); app(FireflyIII\Repositories\User\UserRepositoryInterface::class)->store(["email" => "owner@example.com", "role" => "owner"]);' > /s/aux/ff-user.log 2>&1
    php8.5 artisan firefly-iii:correct-database > /s/aux/ff-c0.log 2>&1
    php8.5 /ap/defines/firefly/make_data.php > /s/aux/ff-data.log 2>&1
    sqlite3 /s/ff/database.sqlite < /ap/defines/firefly/inject.sql
    mkdir -p "$tpl" && cp -a /s/ff/. "$tpl"/
fi
rm -rf /s/ff && mkdir -p /s/ff && cp -a "$tpl"/. /s/ff/
install -m 755 /ap/defines/firefly/check.sh /s/firefly-check.sh
install -m 755 /ap/defines/firefly/check-strict.sh /s/firefly-check-strict.sh
