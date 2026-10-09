set -eu
rm -rf /s/jump /s/jump-dirs && mkdir -p /s/jump /s/jump-dirs/notes /s/jump-dirs/photos /s/jump-dirs/old-project
export JUMP_HOME=/s/jump
for d in notes photos old-project notes photos notes; do (cd /s/jump-dirs/$d && jump chdir); done
jump pin pics /s/jump-dirs/photos
rmdir /s/jump-dirs/old-project
