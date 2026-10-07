set -eu
rm -rf /s/xbps /s/xbps-in && mkdir -p /s/xbps/root/var/db/xbps /s/xbps-in
cat > /s/xbps/root/var/db/xbps/pkgdb-0.38.plist <<'PL'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>coreutils</key>
	<dict>
		<key>architecture</key>
		<string>aarch64</string>
		<key>automatic-install</key>
		<false/>
		<key>pkgver</key>
		<string>coreutils-9.5_1</string>
		<key>short_desc</key>
		<string>GNU core utilities</string>
		<key>state</key>
		<string>installed</string>
	</dict>
	<key>hello</key>
	<dict>
		<key>architecture</key>
		<string>aarch64</string>
		<key>automatic-install</key>
		<false/>
		<key>pkgver</key>
		<string>hello-2.12_1</string>
		<key>short_desc</key>
		<string>Hello world</string>
		<key>state</key>
		<string>installed</string>
	</dict>
</dict>
</plist>
PL
xbps-query -r /s/xbps/root -l > /s/xbps-in/seed.log 2>&1
grep -q hello /s/xbps-in/seed.log
