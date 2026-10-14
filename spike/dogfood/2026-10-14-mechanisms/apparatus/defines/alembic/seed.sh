set -eu
S=/s/al; P=/s/al-aux/proj
rm -rf $S /s/al-aux && mkdir -p $S $P/versions
printf '[alembic]\nscript_location = %s\nsqlalchemy.url = sqlite:///%s/app.db\n' $P $S > $P/alembic.ini
cat > $P/env.py <<'PY'
from alembic import context
from sqlalchemy import engine_from_config, pool

config = context.config
engine = engine_from_config(config.get_section(config.config_ini_section), prefix="sqlalchemy.", poolclass=pool.NullPool)
with engine.connect() as connection:
    context.configure(connection=connection, target_metadata=None, render_as_batch=True)
    with context.begin_transaction():
        context.run_migrations()
PY
cat > $P/versions/r1.py <<'PY'
import sqlalchemy as sa
from alembic import op

revision = "r1"
down_revision = None


def upgrade():
    op.create_table("notes", sa.Column("id", sa.Integer, primary_key=True), sa.Column("body", sa.Text))
PY
cat > $P/versions/r2.py <<'PY'
import sqlalchemy as sa
from alembic import op

revision = "r2"
down_revision = "r1"


def upgrade():
    with op.batch_alter_table("notes") as b:
        b.alter_column("body", new_column_name="text")
        b.add_column(sa.Column("created", sa.Integer, nullable=False, server_default="0"))
PY
python3 -m alembic -c $P/alembic.ini upgrade r1 > /s/al-aux/upgrade-r1.log 2>&1
python3 - <<'PY'
import sqlite3
c = sqlite3.connect("/s/al/app.db")
c.executemany("INSERT INTO notes VALUES (?, ?)", [(i, "note %d" % i) for i in range(1, 101)])
c.commit()
PY
install -m 755 /ap/defines/alembic/check.sh /s/al-aux/check.sh
