# Node's file calls on one thread (docs/apparatus.md); jiti's compiled-config cache off (it writes
# node_modules/.cache/jiti, inside the state, from the main thread: transcripts/lab-s1e.txt); no
# update check.
export UV_THREADPOOL_SIZE=1 JITI_FS_CACHE=false PRISMA_HIDE_UPDATE_MESSAGE=1 CHECKPOINT_DISABLE=1
