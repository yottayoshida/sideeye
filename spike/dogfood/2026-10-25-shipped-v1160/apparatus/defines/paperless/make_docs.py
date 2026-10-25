"""Build the library the define starts from: six documents, three correspondents, each with an
original, an archived version and a thumbnail on disk and a row in db.sqlite3, filed under
Paperless's default names (no PAPERLESS_FILENAME_FORMAT). Run once, through manage.py shell."""
import hashlib
from pathlib import Path
from django.conf import settings
from documents.models import Correspondent, Document
from documents.utils import compute_checksum

people = [Correspondent.objects.create(name=n) for n in ("Tax Office", "Landlord", "Bank")]
for i in range(6):
    c = people[i % 3]
    d = Document.objects.create(title=f"Letter {i + 1}", content=f"text {i + 1}", mime_type="application/pdf",
                                checksum="x", correspondent=c)
    name = f"{d.pk:07}.pdf"
    o = settings.ORIGINALS_DIR / name; a = settings.ARCHIVE_DIR / name
    t = settings.THUMBNAIL_DIR / f"{d.pk:07}.webp"
    for p, body in ((o, b"%PDF-1.4 original " + bytes([65 + i]) * 200), (a, b"%PDF-1.4 archive " + bytes([97 + i]) * 200),
                    (t, b"RIFF thumb" + bytes([i]))):
        p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(body)
    Document.objects.filter(pk=d.pk).update(filename=name, archive_filename=name,
        checksum=compute_checksum(o), archive_checksum=compute_checksum(a))
print("documents:", Document.objects.count())
