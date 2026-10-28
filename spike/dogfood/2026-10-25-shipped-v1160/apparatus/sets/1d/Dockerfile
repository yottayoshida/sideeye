# Set 1's last reserve (transcripts/scout-1.txt): Chroma 1.5.9, the latest on PyPI on 2026-10-25,
# in its own virtualenv.
FROM sideeye-sv1025-s1c
RUN python3 -m venv /opt/chroma && /opt/chroma/bin/pip install --no-cache-dir chromadb==1.5.9 > /tmp/pip-chroma.log 2>&1 && echo "OK chromadb" || { echo "FAILED chromadb"; tail -5 /tmp/pip-chroma.log; }
RUN ln -sf /opt/chroma/bin/chroma /opt/bin/chroma && { cat /versions.txt; echo "chroma $(/opt/chroma/bin/pip show chromadb | sed -n 's/^Version: //p')"; } > /versions.new && mv /versions.new /versions.txt && tail -1 /versions.txt
