import json
import pathlib
import shutil
import subprocess

HERE = pathlib.Path(__file__).parent


def test_no_crash_window(tmp_path):
    sideeye = shutil.which("sideeye")
    assert sideeye, "sideeye is not on PATH"
    report = tmp_path / "report.json"
    run = subprocess.run(
        [sideeye, "explore", "--config", str(HERE / "sideeye.toml"),
         "--oracle", "/usr/bin/strace",
         "--work", str(tmp_path / "work"), "--json", str(report)],
        capture_output=True, text=True,
    )
    assert run.returncode == 0, run.stdout + run.stderr
    result = json.loads(report.read_text())
    assert result["verdict"] == "PASS" and result["oracle_verified"], result
