set -eu
rm -rf /s/yt /s/yt-in /s/yt-out && mkdir -p /s/yt /s/yt-in
python3 -c "import random; random.seed(7); open('/s/yt-in/clip.mp4','wb').write(bytes(random.getrandbits(8) for _ in range(200000)))"
printf 'youtube dQw4w9WgXcQ\nvimeo 76979871\ngeneric holiday-2025\n' > /s/yt/archive.txt
