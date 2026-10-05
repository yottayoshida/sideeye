set -eu
rm -rf /s/sub /s/sub-in && mkdir -p /s/sub /s/sub-in
python3 - <<'P'
def ts(s): h=int(s//3600); m=int(s%3600//60); sec=s%60; return f"{h:02}:{m:02}:{int(sec):02},{int((sec%1)*1000):03}"
ref=[]; sub=[]
for i in range(60):
    a=5+i*7.3; b=a+2.5
    ref.append(f"{i+1}\n{ts(a)} --> {ts(b)}\nline {i}\n")
    sub.append(f"{i+1}\n{ts(a+3.2)} --> {ts(b+3.2)}\nline {i}\n")
open('/s/sub-in/ref.srt','w').write("\n".join(ref)); open('/s/sub/movie.srt','w').write("\n".join(sub))
P
