set -eu
. /ap/defines/paperless/env.sh
# The library is built once per box (migrate, then make_docs.py), and every seed copies that same
# tree back, so every world starts from the same bytes.
tpl=/s/aux/tpl-paperless
if [ ! -f $tpl/data/db.sqlite3 ]; then
    rm -rf $tpl /s/paperless; mkdir -p $PAPERLESS_DATA_DIR $PAPERLESS_MEDIA_ROOT
    cd /opt/paperless-ngx/src
    /opt/paperless-venv/bin/python manage.py migrate --no-input > /s/aux/pl-migrate.log 2>&1
    PAPERLESS_FILENAME_FORMAT= /opt/paperless-venv/bin/python manage.py shell < /ap/defines/paperless/make_docs.py > /s/aux/pl-make.log 2>&1
    rm -f $PAPERLESS_MEDIA_ROOT/media.lock
    mkdir -p $tpl && cp -a /s/paperless/. $tpl/
fi
rm -rf /s/paperless && mkdir -p /s/paperless && cp -a $tpl/. /s/paperless/
for f in check.sh; do install -m 755 /ap/defines/paperless/$f /s/paperless-$f; done
