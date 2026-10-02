"""CI diagnostic: builds small probe projects with the real Rojo to confirm .model.json encodings."""
import re, subprocess, sys, tempfile
from pathlib import Path
here = Path(__file__).parent
for proj in sorted(here.glob("*.project.json")):
    out = Path(tempfile.gettempdir()) / (proj.stem + ".rbxlx")
    r = subprocess.run(["rojo", "build", str(proj), "-o", str(out)], capture_output=True, text=True)
    print("== %s exit=%d" % (proj.name, r.returncode))
    print((r.stdout + r.stderr).strip()[-1500:])
    if r.returncode == 0 and out.exists():
        xml = out.read_text(encoding="utf-8", errors="replace")
        for cls in ("Part", "Terrain", "BillboardGui"):
            m = re.search(r'<Item class="%s".*?</Properties>' % cls, xml, re.S)
            if m:
                print("-- %s:\n%s" % (cls, m.group(0)[:2500]))

