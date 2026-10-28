# Not by mounting an engine: every procedure in these boxes reads /install.path, and engine.txt
# copies /install.log's digest line, so a mounted engine would sit beside the old one's record.
ARG BOX
FROM ${BOX}
RUN sh /opt/install-sideeye.sh v1.15.0 /opt/se15 > /install.path 2>/install.log \
 && "$(cat /install.path)" version \
 && grep -q 'digest matches' /install.log
