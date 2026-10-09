"""Write a legacy-format Hydrogen drumkit: drumkit.xml and two 16-bit mono WAVs, all from fixed values.

    python3 make_kit.py <kit dir>
"""
import struct, sys, wave
from pathlib import Path

d = Path(sys.argv[1]); d.mkdir(parents=True, exist_ok=True)
for n, k in (("kick", 37), ("snare", 53)):
    w = wave.open(str(d / f"{n}.wav"), "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
    w.writeframes(b"".join(struct.pack("<h", (i * k) % 2000 - 1000) for i in range(4410))); w.close()
(d / "drumkit.xml").write_text('''<?xml version="1.0" encoding="UTF-8"?>
<drumkit_info>
 <name>Box Kit</name>
 <author>sideeye</author>
 <info>a two-instrument kit written for the box</info>
 <license>CC0</license>
 <instrumentList>
  <instrument><id>0</id><name>Kick</name><volume>1</volume><isMuted>false</isMuted><pan_L>1</pan_L><pan_R>1</pan_R>
   <layer><filename>kick.wav</filename><min>0</min><max>1</max><gain>1</gain><pitch>0</pitch></layer></instrument>
  <instrument><id>1</id><name>Snare</name><volume>1</volume><isMuted>false</isMuted><pan_L>1</pan_L><pan_R>1</pan_R>
   <layer><filename>snare.wav</filename><min>0</min><max>1</max><gain>1</gain><pitch>0</pitch></layer></instrument>
 </instrumentList>
</drumkit_info>
''')
