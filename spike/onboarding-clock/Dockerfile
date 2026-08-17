# The fresh machine for the onboarding clock (PROTOCOL.md beside this file).
# Build from the repository root so README.md is in the context:
#   docker build -f spike/onboarding-clock/Dockerfile -t sideeye-onboarding .
# Run network-off; the clock never sees this file's network use.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv ca-certificates curl \
      gcc libc6-dev strace \
 && rm -rf /var/lib/apt/lists/*

# The target, installed at build time (deviation 2 in PROTOCOL.md). The
# trusted-host flags are the container-network TLS gotcha this repo has hit
# before (spike/Dockerfile): pip's TLS is MITM'd by the sandbox. The installed
# version is recorded into the run's meta — pinning here would rot silently.
RUN pip3 install --break-system-packages --no-cache-dir \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org jrnl

RUN useradd -m user
WORKDIR /home/user/onboarding

# The release tarball, pinned (deviation 1). -k tolerates the sandbox's TLS
# MITM because integrity comes from the sha256 pin, not the channel: a swapped
# artifact fails the build.
RUN curl -sLk -o sideeye-v0.10.0-aarch64-linux.tar.gz \
      https://github.com/yottayoshida/sideeye/releases/download/v0.10.0/sideeye-v0.10.0-aarch64-linux.tar.gz \
 && echo "4851df145396a94db3bddeedb00050d91d87d4afd5cf0b34147f2230da4ffa27  sideeye-v0.10.0-aarch64-linux.tar.gz" | sha256sum -c -

# The front page at the measured commit, verbatim (deviation 3).
COPY README.md /home/user/onboarding/README.md

# The target arrives configured (deviation 2): the wizard's answers, as a file.
RUN mkdir -p /home/user/.config/jrnl /home/user/journal \
 && printf 'journals:\n  default:\n    journal: /home/user/journal/journal.txt\nencrypt: false\neditor: ""\ncolors:\n  body: none\n  date: none\n  tags: none\n  title: none\ndefault_hour: 9\ndefault_minute: 0\nhighlight: true\nindent_character: "|"\nlinewrap: 79\ntagsymbols: "#@"\ntemplate: false\ntimeformat: "%%Y-%%m-%%d %%H:%%M"\n' \
      > /home/user/.config/jrnl/jrnl.yaml \
 && chown -R user:user /home/user

USER user
CMD ["sleep", "infinity"]
