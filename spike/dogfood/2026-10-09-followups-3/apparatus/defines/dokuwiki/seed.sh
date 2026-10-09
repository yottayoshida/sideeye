set -eu
rm -rf /s/dw /s/dw-in && cp -a /opt/dokuwiki /s/dw && mkdir -p /s/dw-in
printf '====== Start ======\nOur household wiki: the boiler is serviced in March.\n' > /s/dw-in/first.txt
php /s/dw/bin/dwpage.php commit -m first /s/dw-in/first.txt wiki:start > /s/dw-in/seed.log 2>&1
printf '====== Start ======\nOur household wiki: the boiler is serviced in March and October.\n' > /s/dw-in/page.txt
