#!/bin/sh
# After a crash anywhere in write-translations, the translator's work is still there: every JSON
# file under i18n/fr parses, and the French messages they wrote are in code.json and navbar.json.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(docusaurus): $*"; exit 1; }
python3 - "$d/fr" <<'PY' || fail "a translation file is torn or the translator's messages are gone"
import json, pathlib, sys
fr = pathlib.Path(sys.argv[1])
for p in fr.rglob("*.json"):
    json.loads(p.read_text())          # raises on a torn file
code = json.loads((fr / "code.json").read_text())
assert code["theme.NotFound.title"]["message"] == "Page introuvable"
assert code["theme.blog.post.readMore"]["message"] == "Lire la suite"
nav = json.loads((fr / "docusaurus-theme-classic" / "navbar.json").read_text())
assert nav["title"]["message"] == "Mon site"
PY
exit 0
