set -eu
# A ROOT file with three histograms written by ROOT itself; `rootrm data.root:h2` opens it in UPDATE
# mode and rewrites its key list in place (lab 14: O_RDWR, then writes and two fsyncs). The
# histograms are filled from a fixed seed so two seeds write the same bytes.
rm -rf /s/rootf /s/rootf-in && mkdir -p /s/rootf /s/rootf-in && cd /s/rootf
/opt/root/bin/root -b -q -e 'gRandom->SetSeed(1009); TFile f("data.root","RECREATE"); TH1F h1("h1","",10,0,1); h1.FillRandom("gaus",100); h1.Write(); TH1F h2("h2","",10,0,1); h2.FillRandom("gaus",50); h2.Write(); TH1F h3("h3","",10,0,1); h3.Write();' > /s/rootf-seed.log 2>&1 || true
[ -s /s/rootf/data.root ]
