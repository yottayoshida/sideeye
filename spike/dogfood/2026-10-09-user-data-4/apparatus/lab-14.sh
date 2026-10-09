#!/bin/sh
# Lab 14: the seventh layer by hand under strace — ifcpatch writing a model back to its input,
# rootrm deleting a key from a ROOT file, CKAN's compatible versions, Hydrogen's drumkit upgrade.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-14.sh
set -u
. /ap/env.sh
O=/out/lab-14; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T,clone,clone3,execve -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines; $(grep -c -E 'clone3?\(' "$O/$n.strace") clone; $(grep -c 'execve(' "$O/$n.strace") execve"
    grep -E 'O_TRUNC|O_CREAT|O_APPEND|rename|unlink|link\(|truncate|fsync|pwrite64' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale|__pycache__|\.pyc' | head -${MAXL:-14}
    tail -3 "$O/$n.out" | cut -c1-200
}

echo "## ifcpatch"
rm -rf /s/ifc && mkdir -p /s/ifc && cd /s/ifc
/opt/py/bin/python3 - > "$O/ifc-seed.out" 2>&1 <<'PY'
import ifcopenshell, ifcopenshell.api
f = ifcopenshell.api.run("root.create_file", version="IFC4")
p = ifcopenshell.api.run("root.create_entity", f, ifc_class="IfcProject", name="House")
ifcopenshell.api.run("unit.assign_unit", f)
site = ifcopenshell.api.run("root.create_entity", f, ifc_class="IfcSite", name="Site")
b = ifcopenshell.api.run("root.create_entity", f, ifc_class="IfcBuilding", name="Building")
ifcopenshell.api.run("aggregate.assign_object", f, relating_object=p, products=[site])
ifcopenshell.api.run("aggregate.assign_object", f, relating_object=site, products=[b])
for i in range(5):
    w = ifcopenshell.api.run("root.create_entity", f, ifc_class="IfcWall", name=f"Wall {i}")
    ifcopenshell.api.run("spatial.assign_container", f, relating_structure=b, products=[w])
f.write("/s/ifc/model.ifc")
PY
echo "seed exit $?"; ls -l /s/ifc; /opt/py/bin/python3 -m ifcpatch --help 2>&1 | head -12
tr_ ifcpatch /opt/py/bin/python3 -m ifcpatch -i model.ifc -r RegenerateGlobalIds
ls -l /s/ifc

echo "## rootrm"
rm -rf /s/rootf && mkdir -p /s/rootf && cd /s/rootf
export PATH=/opt/root/bin:$PATH
root -b -q -e 'TFile f("data.root","RECREATE"); TH1F h1("h1","",10,0,1); h1.FillRandom("gaus",100); h1.Write(); TH1F h2("h2","",10,0,1); h2.Write(); TH1F h3("h3","",10,0,1); h3.Write();' > "$O/root-seed.out" 2>&1; echo "seed exit $?"; ls -l
rootls data.root 2>&1 | head -5
tr_ rootrm rootrm data.root:h2
ls -l; rootls data.root 2>&1 | head -5

echo "## ckan"
rm -rf /s/ksp /s/aux/home/.local/share/CKAN && mkdir -p /s/ksp && cd /s/ksp
ckan instance fake box /s/ksp/game 1.12.5 --set-default --headless > "$O/ckan-seed.out" 2>&1; echo "seed exit $?"; tail -3 "$O/ckan-seed.out"
find /s/ksp/game/CKAN -maxdepth 1 -type f 2>/dev/null | head
tr_ ckan ckan compat add 1.11 --headless
cat /s/ksp/game/CKAN/compatible_game_versions.json 2>/dev/null | head -12

echo "## h2cli"
rm -rf /s/h2 && mkdir -p /s/h2/kit && cd /s/h2
python3 - <<'PY'
import struct, wave
for n in ("kick", "snare"):
    w = wave.open(f"/s/h2/kit/{n}.wav", "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
    w.writeframes(b"".join(struct.pack("<h", (i * 37) % 2000 - 1000) for i in range(4410))); w.close()
open("/s/h2/kit/drumkit.xml", "w").write('''<?xml version="1.0" encoding="UTF-8"?>
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
PY
h2cli --help 2>&1 | grep -E -- '-u|upgrade|-t|drumkit' | head -6
tr_ h2cli h2cli -u /s/h2/kit
ls -la /s/h2/kit; head -5 /s/h2/kit/drumkit.xml
