export CODEX_HOME=/s/codex

# One rayon worker and one tokio worker, to see whether the threads wall moves (a tokio runtime still
# runs its file calls on a separate blocking pool, so this may not be enough).
export RAYON_NUM_THREADS=1 TOKIO_WORKER_THREADS=1
