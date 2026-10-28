<!--
Draft for hashicorp/vagrant, 2026-10-25. Not filed.
Policy read: .github/CONTRIBUTING.md (no rule on AI-written text; points to the HashiCorp community guidelines, whose page carries none either) and .github/ISSUE_TEMPLATE/bug-report.md (Markdown, no required fields; every heading filled).
Freshness: tracker searched one word at a time (machine-index, global-status, prune, JSON::ParserError, truncated): #6680 is corrupt JSON reported as an error; #11864 unrelated. Owner's prior filings here: 0.
Latest release v2.4.9 (measured). Source at v2.4.9: lib/vagrant/machine_index.rb unlocked_save / unlocked_reload.
Reproduced without Sideeye: transcripts/plain-repro-s3.txt; recovery through the project: transcripts/plain-repro-s3-vagrant-recover.txt.
Title: Machine index left empty if vagrant is killed while saving it; later runs read it as "no environments"
-->

### Debug output

Not attached: the run is killed in the middle of a write, so its log stops at that write.

### Expected behavior

A kill while the machine index is saved leaves either the old index or the new one.

### Actual behavior

No data is lost by this, but the index is left at 0 bytes and Vagrant then reads it as empty, with no error: `vagrant global-status` reports no environments, and the next save makes the empty index permanent. A machine reappears only when Vagrant is run in its own project directory.

`unlocked_save` in `lib/vagrant/machine_index.rb` truncates the index with `open("w")` before writing. `unlocked_reload` raises `CorruptMachineIndex` on bad JSON, but `JSON.load("")` returns `nil`, so an empty file passes silently. #6680 is the corrupt-JSON case, which does raise an error.

A possible fix: write a temporary file in the same directory and rename it over the index, or treat an empty index as corrupt.

### Reproduction information

#### Vagrant version

2.4.9, built from the v2.4.9 tag as a gem (there is no Linux arm64 installer); Ruby 3.3.8.

#### Host operating system

Debian 13, aarch64, in a container.

#### Guest operating system

None: a stand-in `VBoxManage` on `PATH` reports one machine as running.

#### Steps to reproduce

1. A machine index (1,978 bytes) with six entries: five whose project directories are gone, and one live machine, `web`.
2. `strace -f -P ~/.vagrant.d/data/machine-index/index -e inject=write:signal=KILL vagrant global-status --prune` (SIGKILL at the first `write` after the truncating open).
3. The index is 0 bytes, and `vagrant global-status` lists nothing (exit 0). Without the kill, the index keeps `web` (390 bytes).

#### Vagrantfile

    Vagrant.configure("2") do |config|
      config.vm.box = "bento/debian-13"
      config.vm.define "web"
    end

Found with Sideeye (https://github.com/yottayoshida/sideeye), my personal open-source crash-consistency tool, with no commercial interest; drafted with AI assistance and checked by me.
