set -eu
. /ap/defines/navidrome/env.sh
# The library a listener has used for a while, built once per box: two albums scanned, the schema
# made by one short start of the server (the scan command makes none), an admin, and a play count,
# rating and star on every track. Then a third album lands in the music folder, which is what the
# operation's full rescan picks up. Every seed copies that same data folder back.
tpl=/s/aux/tpl-nd
if [ ! -f $tpl/navidrome.db ]; then
    rm -rf /s/nd /s/aux/music $tpl; mkdir -p /s/nd /s/aux/music
    python3 /ap/defines/navidrome/make_flac.py /s/aux/music 2 > /dev/null
    cd /s/nd
    ND_ADDRESS=127.0.0.1 ND_SCANNER_ENABLED=false ND_DEVAUTOCREATEADMINPASSWORD=hunter22 /opt/bin/navidrome > /s/aux/nd-server.log 2>&1 & pid=$!
    sleep 6; kill $pid; wait $pid || true
    /opt/bin/navidrome scan --full > /s/aux/nd-scan0.log 2>&1
    sqlite3 /s/nd/navidrome.db "insert into annotation (user_id, item_id, item_type, play_count, play_date, rating, starred, starred_at, rated_at)
        select u.id, m.id, 'media_file', 10 + m.track_number, '2026-10-01 12:00:00', 1 + m.track_number, 1, '2026-10-01 12:00:00', '2026-10-01 12:00:00'
        from media_file m, user u where u.user_name = 'admin'"
    python3 /ap/defines/navidrome/make_flac.py /s/aux/music 3 > /dev/null
    mkdir -p $tpl && cp -a /s/nd/. $tpl/
fi
rm -rf /s/nd && mkdir -p /s/nd && cp -a $tpl/. /s/nd/
install -m 755 /ap/defines/navidrome/check.sh /s/navidrome-check.sh
