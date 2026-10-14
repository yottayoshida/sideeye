set -eu
S=/s/dj; P=/s/dj-aux/proj
rm -rf $S /s/dj-aux && mkdir -p $S $P/app/migrations
cat > $P/settings.py <<'PY'
SECRET_KEY = "not-a-secret"
INSTALLED_APPS = ["app"]
DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": "/s/dj/db.sqlite3"}}
USE_TZ = True
DEFAULT_AUTO_FIELD = "django.db.models.AutoField"
PY
cat > $P/manage.py <<'PY'
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "settings")
from django.core.management import execute_from_command_line
execute_from_command_line(sys.argv)
PY
: > $P/app/__init__.py
: > $P/app/migrations/__init__.py
cat > $P/app/models.py <<'PY'
PY
cat > $P/app/migrations/0001_initial.py <<'PY'
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = []
    operations = [
        migrations.CreateModel(name="Note", fields=[
            ("id", models.AutoField(primary_key=True)),
            ("body", models.TextField()),
            ("rank", models.CharField(max_length=10)),
        ]),
    ]
PY
cat > $P/app/migrations/0002_change.py <<'PY'
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("app", "0001_initial")]
    operations = [
        migrations.RenameField("Note", "body", "text"),
        migrations.AlterField("Note", "rank", models.IntegerField()),
    ]
PY
python3 $P/manage.py migrate app 0001 > /s/dj-aux/migrate-0001.log 2>&1
python3 - <<'PY'
import sqlite3
c = sqlite3.connect("/s/dj/db.sqlite3")
c.executemany("INSERT INTO app_note (id, body, rank) VALUES (?, ?, ?)", [(i, "note %d" % i, str(i)) for i in range(1, 101)])
c.commit()
PY
install -m 755 /ap/defines/django/check.sh /s/dj-aux/check.sh
