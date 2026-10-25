set -eu
# A project with drizzle-kit 0.31.11, drizzle-orm 0.45.4 and better-sqlite3 13.0.3 (installed in the
# box), two hand-written migrations, and a database the first one built and the app filled.
rm -rf /s/dz && mkdir -p /s/dz/db /s/dz/drizzle/meta && cd /s/dz
ln -s /opt/drizzle-proj/node_modules node_modules
cat > drizzle.config.ts <<'TS'
import { defineConfig } from "drizzle-kit";
export default defineConfig({ dialect: "sqlite", out: "./drizzle", dbCredentials: { url: "./db/app.db" } });
TS
cat > drizzle/0000_init.sql <<'SQL'
CREATE TABLE `notes` (`id` integer PRIMARY KEY NOT NULL, `title` text NOT NULL, `body` text NOT NULL);
SQL
cat > drizzle/0001_tags.sql <<'SQL'
ALTER TABLE `notes` ADD `archived` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
CREATE TABLE `tags` (`id` integer PRIMARY KEY NOT NULL, `note_id` integer NOT NULL REFERENCES `notes`(`id`), `name` text NOT NULL);--> statement-breakpoint
INSERT INTO `tags` (`note_id`, `name`) SELECT `id`, 'imported' FROM `notes`;--> statement-breakpoint
UPDATE `notes` SET `archived` = 1 WHERE `title` LIKE 'old:%';
SQL
journal() { python3 - "$@" <<'PY'
import json, sys
tags = sys.argv[1:]
e = [{"idx": i, "version": "6", "when": 1760000000000 + i * 1000, "tag": t, "breakpoints": True} for i, t in enumerate(tags)]
open("/s/dz/drizzle/meta/_journal.json", "w").write(json.dumps({"version": "7", "dialect": "sqlite", "entries": e}, indent=2) + "\n")
PY
}
journal 0000_init
node node_modules/drizzle-kit/bin.cjs migrate --config drizzle.config.ts > /s/dz-seed-migrate.log 2>&1
python3 - <<'PY'
import sqlite3
c = sqlite3.connect("/s/dz/db/app.db")
c.executemany("insert into notes(title, body) values (?, ?)",
    [(f"{'old:' if i % 3 == 0 else ''}note {i}", f"The body of note {i}, written by its owner. " * 4) for i in range(1, 121)])
c.commit(); c.close()
PY
journal 0000_init 0001_tags
install -m 755 /ap/defines/drizzle-kit/check.sh /s/dz-check.sh
