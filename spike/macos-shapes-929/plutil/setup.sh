#!/bin/sh
set -eu
cat > "$SIDEEYE_STATE_DIR/prefs.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>name</key>
	<string>sideeye-shapes</string>
	<key>retries</key>
	<integer>3</integer>
	<key>enabled</key>
	<true/>
	<key>mode</key>
	<string>steady</string>
	<key>owner</key>
	<string>ops</string>
</dict>
</plist>
EOF
