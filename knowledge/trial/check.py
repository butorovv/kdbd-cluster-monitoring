"""Run both independent trials and compare their answers against shared expectations."""
import csv
import json
from pathlib import Path
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent


def check(name, command, expected):
    result = subprocess.run(command, cwd=HERE, check=True, capture_output=True, text=True)
    if json.loads(result.stdout) != expected:
        raise SystemExit(f"{name}: результат отличается от expected.json\n{result.stdout}")
    print(f"{name}: 6 ожидаемых ответов подтверждены")


def main():
    with (HERE.parent / "knowledge.csv").open(encoding="utf-8-sig") as catalog:
        ids = {row["id"] for row in csv.DictReader(catalog)}
    shared = json.loads((HERE / "scenarios.json").read_text(encoding="utf-8"))["knowledge"].values()
    if len(set(shared)) < 10 or not set(shared) <= ids:
        raise SystemExit("В сценариях должны быть минимум 10 ID из каталога.")
    expected = json.loads((HERE / "expected.json").read_text(encoding="utf-8"))
    check("Python", [sys.executable, "production.py"], expected)
    swipl = shutil.which("swipl")
    if swipl is None:
        raise SystemExit("SWI-Prolog не найден в PATH.")
    check("SWI-Prolog", [swipl, "-q", "-s", "logic.pl"], expected)


if __name__ == "__main__":
    main()
