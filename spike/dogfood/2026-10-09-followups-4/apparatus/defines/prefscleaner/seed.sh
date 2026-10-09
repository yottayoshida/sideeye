set -eu
# A Firefox profile directory holding arkenfox's user.js, a five-line prefs.js with two entries
# user.js also sets, and the script itself — the layout arkenfox documents. The script refuses
# root (lab 3) and refuses when any file is root's (lab 4), so the directory is chowned to an
# unprivileged user and the operation runs through setpriv.
rm -rf /s/ffprofile && mkdir -p /s/ffprofile
cp /opt/arkenfox/user.js /s/ffprofile/user.js
cp /opt/arkenfox/prefsCleaner.sh /s/ffprofile/prefsCleaner.sh
printf '// Mozilla User Preferences\n\nuser_pref("app.update.auto", false);\nuser_pref("browser.startup.homepage", "https://example.org");\nuser_pref("privacy.resistFingerprinting", false);\nuser_pref("browser.download.dir", "/s/downloads");\nuser_pref("network.cookie.cookieBehavior", 0);\n' > /s/ffprofile/prefs.js
chown -R 1000:1000 /s/ffprofile
grep -q cookieBehavior /s/ffprofile/prefs.js
