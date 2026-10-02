# The static map sources (src/Workspace/Map) are generated from GameConfig.json by
# tools/gen_static_map.py (CI runs it before the real `rojo build`). Generate them here when they
# are missing so the test suite also works on a fresh checkout.
from pathlib import Path as _Path
import subprocess as _subprocess
import sys as _sys

_ROOT = _Path(__file__).resolve().parent.parent
if not (_ROOT / "src" / "Workspace" / "Map" / "CentralIsland.model.json").is_file():
    _subprocess.run([_sys.executable, str(_ROOT / "tools" / "gen_static_map.py")], cwd=str(_ROOT), check=True)

