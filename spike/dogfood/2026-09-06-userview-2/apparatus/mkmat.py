import wave, struct, math

w = wave.open('/work/d/a.wav', 'wb')
w.setnchannels(1)
w.setsampwidth(2)
w.setframerate(8000)
w.writeframes(b''.join(struct.pack('<h', int(10000 * math.sin(i / 10.0)))
                       for i in range(8000)))
w.close()
print('wav written')
