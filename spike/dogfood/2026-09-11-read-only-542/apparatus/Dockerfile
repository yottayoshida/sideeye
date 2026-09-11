# The ocrmypdf half of the 2026-09-11 dogfood image, rebuilt for this run: that run's
# Dockerfile (spike/dogfood/2026-09-11-past-walls/apparatus/Dockerfile) copies an oxipng
# and a Bun binary from the host, which this host no longer has, so it cannot be built
# again as it stands. Same base and the same apt packages for the targets that matter here.
#
#   docker build -t sideeye-ocrmypdf:2026-09-11 .
#
# mlr runs in the other image this run used, sideeye-reach:2026-09-07, built from
# spike/followup-item4/Dockerfile unchanged.
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      strace file python3 ca-certificates procps ocrmypdf tesseract-ocr-eng ghostscript
WORKDIR /w
