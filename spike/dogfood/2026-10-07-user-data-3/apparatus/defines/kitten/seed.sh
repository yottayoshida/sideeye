set -eu
rm -rf /s/aux/home/.config/kitty /s/aux/cache/kitty /s/kitten-in && mkdir -p /s/aux/home/.config/kitty /s/aux/cache/kitty /s/kitten-in
printf '# my kitty.conf, written by hand\nfont_family JetBrains Mono\nfont_size 13.0\nmap ctrl+shift+t new_tab_with_cwd\n' > /s/aux/home/.config/kitty/kitty.conf
# The theme archive was fetched at build; kitten reads its cache age from a JSON comment in the zip
# (tools/themes/collection.go, fetch_cached), so the copy carries one.
cp /opt/kitty-themes/kitty-themes.zip /s/aux/cache/kitty/kitty-themes.zip
/opt/py/bin/python -I -c "import zipfile; z=zipfile.ZipFile('/s/aux/cache/kitty/kitty-themes.zip','a'); z.comment=b'{\"etag\":\"seed\",\"timestamp\":\"2026-10-07T00:00:00.000000000+00:00\"}'; z.close()"
test -s /s/aux/home/.config/kitty/kitty.conf
