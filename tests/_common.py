import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
CONFIG = SRC / "ReplicatedStorage" / "Shared" / "Config"


def load_json(name):
    with open(CONFIG / name, encoding="utf-8") as f:
        return json.load(f)


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def luau_files():
    return sorted(list(SRC.rglob("*.luau")) + list((ROOT / "plugin").rglob("*.luau")))

