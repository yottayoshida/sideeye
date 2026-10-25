set -eu
# The classic template (create-docusaurus 3.10.2, installed in the box) with French enabled, and a
# translation in progress: every message the translator has done is French, and the strings the site
# gained since (the footer, the blog options) are not there yet.
rm -rf /s/docu && mkdir -p /s/docu && cd /opt/docusite
tar cf - --exclude=node_modules --exclude=.docusaurus --exclude=build . | tar xf - -C /s/docu
ln -s /opt/docusite/node_modules /s/docu/node_modules && cd /s/docu
sed -i 's/locales: \[.en.\]/locales: ["en", "fr"]/' docusaurus.config.js
NO_UPDATE_NOTIFIER=1 node node_modules/@docusaurus/core/bin/docusaurus.mjs write-translations --locale fr > /dev/null 2>&1
rm -rf .docusaurus i18n/fr/docusaurus-theme-classic/footer.json i18n/fr/docusaurus-plugin-content-blog
python3 - <<'PY'
import json, pathlib
fr = pathlib.Path("/s/docu/i18n/fr")
code = fr / "code.json"
d = json.loads(code.read_text())
done = {"theme.NotFound.title": "Page introuvable",
        "theme.common.editThisPage": "Modifier cette page",
        "theme.docs.paginator.next": "Suivant",
        "theme.docs.paginator.previous": "Précédent",
        "theme.blog.post.readMore": "Lire la suite"}
for k, v in done.items():
    d[k]["message"] = v
# Strings added to the site after the translator's last pass: absent from the file.
for k in list(d)[-40:]:
    if k not in done: del d[k]
code.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
nav = fr / "docusaurus-theme-classic" / "navbar.json"
n = json.loads(nav.read_text())
n["title"]["message"] = "Mon site"
n["item.label.Tutorial"]["message"] = "Tutoriel"
nav.write_text(json.dumps(n, ensure_ascii=False, indent=2) + "\n")
PY
install -m 755 /ap/defines/docusaurus/check.sh /s/docu-check.sh
