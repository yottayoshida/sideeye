FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends strace build-essential python3 procps file ca-certificates > /tmp/apt.log 2>&1 && strace -V | head -1
