# 2026-09-27's jj define (spike/dogfood/2026-09-27-supervised-static/apparatus/run.sh): the pins of
# jj's documented reproducibility environment, HOME outside the state, and jj 0.46.0 first on PATH so the
# checker reads the repository with the same release.
export JJ_USER=probe JJ_EMAIL=probe@example.invalid JJ_TIMESTAMP=2026-01-01T00:00:00+00:00 \
    JJ_OP_TIMESTAMP=2026-01-01T00:00:00+00:00 JJ_RANDOMNESS_SEED=42 JJ_OP_HOSTNAME=probe-host \
    JJ_OP_USERNAME=probe-user JJ_TZ_OFFSET_MINS=0 HOME=/s/jj-home
export PATH=/opt/jj-0.46.0:$PATH
