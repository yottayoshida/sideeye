set -eu
rm -rf /s/snd /s/snd-in && mkdir -p /s/snd /s/snd-in
/opt/py/bin/python -I -c "import wave,struct; w=wave.open('/s/snd/a.wav','wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b''.join(struct.pack('<h',(i*37)%3000) for i in range(16000))); w.close()"
test -s /s/snd/a.wav
