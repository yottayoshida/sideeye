set -eu
rm -rf /s/babel && mkdir -p /s/babel/translations/ja/LC_MESSAGES /s/babel/translations/fr/LC_MESSAGES && cd /s/babel
hdr='msgid ""\nmsgstr ""\n"Project-Id-Version: demo 1.0\\n"\n"POT-Creation-Date: 2026-09-01 00:00+0000\\n"\n"MIME-Version: 1.0\\n"\n"Content-Type: text/plain; charset=utf-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n'
printf "$hdr"'msgid "Hello"\nmsgstr ""\n\nmsgid "Save"\nmsgstr ""\n\nmsgid "Delete"\nmsgstr ""\n' > messages.pot
printf "$hdr"'msgid "Hello"\nmsgstr "こんにちは"\n\nmsgid "Save"\nmsgstr "保存"\n\nmsgid "Quit"\nmsgstr "終了"\n' > translations/ja/LC_MESSAGES/messages.po
printf "$hdr"'msgid "Hello"\nmsgstr "Bonjour"\n\nmsgid "Save"\nmsgstr "Enregistrer"\n' > translations/fr/LC_MESSAGES/messages.po
