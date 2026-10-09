# topydo/topydo#341, the report's steps on 0.16.
mkdir -p /work/td && cd /work/td
T="/opt/py/bin/topydo -t todo.txt -d done.txt"
$T add seed-task; $T add water-plants
printf '%s seed-task\n' "$(date +%F)" > todo.txt
$T ls
$T revert
echo "--- ls after revert"; $T ls; echo "--- todo.txt: $(wc -c < todo.txt) bytes"; cat todo.txt
