set -eu
# A FreshRSS instance's data directory, installed with its own CLI on SQLite, with one user: data/config.php
# holds the instance's settings and its `salt`, which every stored password hash depends on. The
# salt is copied outside the state so the checker can compare it.
rm -rf /s/freshrss /s/freshrssaux && mkdir -p /s/freshrssaux
cp -a /opt/freshrss/data /s/freshrss
. /ap/defines/freshrss/env.sh
php /opt/freshrss/cli/do-install.php --default-user alice --auth-type form --environment production \
    --base-url https://rss.home.example --language en --title "Alice's feeds" --db-type sqlite > /s/freshrssaux/install.log 2>&1
php /opt/freshrss/cli/create-user.php --user alice --password 'example-pass-1' --language en >> /s/freshrssaux/install.log 2>&1
php -r '$c = include "/s/freshrss/config.php"; echo $c["salt"];' > /s/freshrssaux/salt
test -s /s/freshrssaux/salt
