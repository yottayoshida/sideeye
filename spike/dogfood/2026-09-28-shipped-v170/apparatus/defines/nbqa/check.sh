#!/bin/sh
# The notebook must still load as a notebook with its one code cell, and the cell must still
# hold both statements, reformatted or not.
exec python3 - <<'P'
import json, sys
try:
    nb = json.load(open("/s/nbqa/proj/nb.ipynb"))
except Exception as e:
    sys.exit("nb.ipynb is not JSON: %s" % e)
if nb.get("nbformat") != 4 or len(nb.get("cells", [])) != 1:
    sys.exit("nb.ipynb is not the one-cell notebook it was")
src = "".join(nb["cells"][0]["source"])
for want in ("x = {", "def f("):
    if want not in src:
        sys.exit("the cell lost %r" % want)
P
