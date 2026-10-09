set -eu
rm -rf /s/mu /s/mu-in && mkdir -p /s/mu-in /s/mu/home
for d in inbox archive; do mkdir -p /s/mu/Maildir/$d/cur /s/mu/Maildir/$d/new /s/mu/Maildir/$d/tmp; done
for n in 1001 1002 1003; do
  printf 'From: a@example.org\nTo: me@example.org\nSubject: message %s\nDate: Thu, 01 Oct 2026 10:00:00 +0000\nMessage-ID: <%s@example.org>\n\nbody of %s\n' $n $n $n > "/s/mu/Maildir/inbox/cur/$n.msg:2,S"
done
mu init --muhome /s/mu/home --maildir /s/mu/Maildir > /dev/null
mu index --muhome /s/mu/home > /dev/null
