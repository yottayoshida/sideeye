set -eu
rm -rf /s/nbqa && mkdir -p /s/nbqa/proj && cd /s/nbqa/proj
cat > nb.ipynb <<'J'
{"cells": [{"cell_type": "code", "execution_count": null, "id": "c1", "metadata": {}, "outputs": [], "source": ["x = {'a':1,'b':2}\n", "def f( y ):\n", "    return y+1"]}], "metadata": {"language_info": {"name": "python"}}, "nbformat": 4, "nbformat_minor": 5}
J
