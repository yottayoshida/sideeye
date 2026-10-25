# A Prisma 7.10.1 project on SQLite whose schema.prisma the user wrote by hand — model names, @map,
# a doc comment — and a database that has gained a column and a table since (db pull's case).
set -eu
rm -rf /s/shop && mkdir -p /s/shop/prisma && cd /s/shop
ln -s /opt/prisma-proto/node_modules node_modules
cp /opt/prisma-proto/package.json package.json
cat > prisma.config.ts <<'TS'
import { defineConfig } from "prisma/config";
export default defineConfig({
  schema: "prisma/schema.prisma",
  datasource: { url: "file:./prisma/dev.db" },
});
TS
cat > prisma/schema.prisma <<'PRISMA'
// The shop's data model. Hand-written: the model names and the @map/@@map below are ours.
generator client {
  provider = "prisma-client"
  output   = "../generated/prisma"
}

datasource db {
  provider = "sqlite"
}

/// A customer of the shop.
model Customer {
  id     Int     @id @default(autoincrement())
  email  String  @unique
  name   String  @map("full_name")
  orders Order[]

  @@map("customers")
}

/// An order placed by a customer.
model Order {
  id         Int      @id @default(autoincrement())
  cents      Int
  customerId Int      @map("customer_id")
  customer   Customer @relation(fields: [customerId], references: [id])

  @@map("orders")
}
PRISMA
sqlite3 prisma/dev.db <<'SQL'
CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL, full_name TEXT NOT NULL, phone TEXT);
CREATE UNIQUE INDEX customers_email_key ON customers(email);
CREATE TABLE orders (id INTEGER PRIMARY KEY AUTOINCREMENT, cents INTEGER NOT NULL, customer_id INTEGER NOT NULL REFERENCES customers(id), note TEXT);
CREATE TABLE refunds (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER NOT NULL REFERENCES orders(id), cents INTEGER NOT NULL);
INSERT INTO customers(email, full_name) VALUES ('a@example.invalid','A'),('b@example.invalid','B');
INSERT INTO orders(cents, customer_id) VALUES (100,1),(250,2);
SQL
cat > /s/prisma-check.sh <<'CHK'
#!/bin/sh
# The schema still validates, and the names the user mapped by hand are still mapped.
cd "$SIDEEYE_STATE_DIR" || exit 1
out=$(JITI_FS_CACHE=false /opt/node/bin/node /opt/prisma-proto/node_modules/prisma/build/index.js validate 2>&1) || { echo "falsify: prisma validate: $(echo "$out" | tail -3 | tr '\n' ' ') ($(wc -c < prisma/schema.prisma) bytes)"; exit 1; }
for m in '@@map("customers")' '@@map("orders")' '@map("full_name")' '@map("customer_id")'; do
  grep -qF "$m" prisma/schema.prisma || { echo "falsify: $m is gone from schema.prisma"; exit 1; }
done
exit 0
CHK
chmod 755 /s/prisma-check.sh
