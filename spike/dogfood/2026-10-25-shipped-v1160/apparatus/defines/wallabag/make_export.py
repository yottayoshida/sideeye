import json, sys
# A wallabag v2 JSON export of n entries starting at index k: what `wallabag:export` writes and
# `wallabag:import --importer=v2` reads.
k, n, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
entries = []
for i in range(k, k + n):
    entries.append({
        "is_archived": i % 2, "is_starred": 1 if i % 3 == 0 else 0, "tags": ["reading", "batch-%d" % (k // 10)],
        "title": "Saved article %d" % i, "url": "https://blog.example/posts/%d" % i,
        "content": "<p>" + ("Paragraph %d of a saved article. " % i) * 40 + "</p>",
        "created_at": "2026-10-%02dT08:00:00+00:00" % (1 + i % 20), "updated_at": "2026-10-%02dT08:00:00+00:00" % (1 + i % 20),
        "mimetype": "text/html", "language": "en", "reading_time": 3, "domain_name": "blog.example",
        "preview_picture": None, "http_status": "200", "headers": None, "annotations": [
            {"text": "note on %d" % i, "quote": "Paragraph %d" % i, "ranges": [{"start": "/p[1]", "startOffset": "0", "end": "/p[1]", "endOffset": "11"}]}]})
json.dump(entries, open(out, "w"))
