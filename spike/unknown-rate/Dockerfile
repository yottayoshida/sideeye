# The third sweep image (#84): what the committed campaign and assisted
# images do not carry — the dogfood recipes' targets (timewarrior, todoman,
# watson; install lines taken from each recipe's own header) and the
# B-group targets that reached the define stage. Like the assisted image,
# this is pinned by BUILD, not by manifest: the base tag and the apt
# archive move, so what a sweep actually ran is recorded in its
# artifacts/apparatus.txt and manifest, never claimed from this file.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        strace \
        python3 \
        python3-pip \
        ca-certificates \
        timewarrior \
        2vcard \
        bogofilter-bdb \
        bogofilter-sqlite \
        cookietool \
        emboss \
        hnb \
        lbdb \
    && rm -rf /var/lib/apt/lists/*

# The dogfood recipes' pip targets, pinned as their headers pin them
# (todoman 4.1 + pytz — undeclared runtime dependency, see the recipe;
# watson is td-watson). The trusted-host flags are this host's TLS
# interception, the same note spike/Dockerfile carries.
RUN pip3 install --break-system-packages \
      --trusted-host pypi.org --trusted-host files.pythonhosted.org \
      todoman==4.1 pytz td-watson

WORKDIR /work
