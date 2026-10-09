"""決定的な wav を書く。素材は毎 world 作り直されるので、バイト単位で同じでなければ
baseline がぶれる（watson の baseline_violates_invariant がその形）。"""
import math
import struct
import sys
import wave

path = sys.argv[1]
w = wave.open(path, 'wb')
w.setnchannels(1)
w.setsampwidth(2)
w.setframerate(8000)
w.writeframes(b''.join(struct.pack('<h', int(10000 * math.sin(i / 10.0)))
                       for i in range(4000)))
w.close()
