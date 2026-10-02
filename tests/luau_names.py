# Heuristic "undefined identifier" check for Luau files (catches typos in local names).
# A bare identifier (not a field after '.' / ':' and not a table key) must be declared somewhere in
# the file (local / function / parameter / for variable) or be a known Roblox / Luau global.

try:
    from .luau_parser import tokenize
except ImportError:  # executed as a plain script
    from luau_parser import tokenize

ROBLOX_GLOBALS = {
    "game", "workspace", "script", "plugin", "shared", "Instance", "Vector3", "Vector2", "CFrame",
    "Color3", "UDim", "UDim2", "Enum", "TweenInfo", "ColorSequence", "ColorSequenceKeypoint",
    "NumberSequence", "NumberSequenceKeypoint", "NumberRange", "Random", "RaycastParams",
    "OverlapParams", "Ray", "Rect", "Region3", "BrickColor", "PhysicalProperties", "DateTime",
    "Font", "Faces", "Axes", "math", "string", "table", "task", "utf8", "os", "coroutine", "debug",
    "bit32", "buffer", "pairs", "ipairs", "next", "type", "typeof", "tostring", "tonumber", "print",
    "warn", "error", "assert", "pcall", "xpcall", "select", "setmetatable", "getmetatable",
    "require", "rawget", "rawset", "rawequal", "rawlen", "unpack", "tick", "time", "elapsedTime",
    "self", "_G", "export", "continue", "any", "number", "boolean", "never", "unknown",
}


def undefined_names(src):
    toks = tokenize(src)
    declared = set()
    # pass 1: declarations
    for i, t in enumerate(toks):
        if t.kind == "keyword" and t.value in ("local", "for") or (t.kind == "op" and t.value in ("(", ",")):
            j = i + 1
            if t.kind == "keyword" and t.value == "local" and toks[j].value == "function":
                j += 1
            while j < len(toks) and toks[j].kind == "name":
                declared.add(toks[j].value)
                # skip optional type annotation up to ',' / '=' / 'in' / ')'
                k = j + 1
                if toks[k].value == ":" and t.value != "(" and t.value != ",":
                    depth = 0
                    k += 1
                    while k < len(toks):
                        v = toks[k].value
                        if v in ("(", "{", "<"):
                            depth += 1
                        elif v in (")", "}", ">"):
                            if depth == 0:
                                break
                            depth -= 1
                        elif depth == 0 and v in (",", "=", "in"):
                            break
                        k += 1
                if toks[k].value == ",":
                    j = k + 1
                    continue
                break
        if t.kind == "keyword" and t.value == "function" and toks[i + 1].kind == "name":
            declared.add(toks[i + 1].value)
        if t.kind == "name" and t.value == "type" and toks[i + 1].kind == "name":
            declared.add(toks[i + 1].value)
    # function parameters: names inside '(' ... ')' right after 'function' [name{.name}[:name]]
    for i, t in enumerate(toks):
        if t.kind == "keyword" and t.value == "function":
            j = i + 1
            while toks[j].kind == "name" or toks[j].value in (".", ":"):
                j += 1
            if toks[j].value == "(":
                j += 1
                depth = 0
                expect_name = True
                while j < len(toks):
                    v = toks[j].value
                    if v in ("(", "{", "<"):
                        depth += 1
                    elif v in (")", "}", ">"):
                        if depth == 0:
                            break
                        depth -= 1
                    elif depth == 0 and v == ",":
                        expect_name = True
                        j += 1
                        continue
                    if expect_name and toks[j].kind == "name" and depth == 0:
                        declared.add(v)
                        expect_name = False
                    elif v == ":":
                        expect_name = False
                    j += 1
    # pass 2: uses
    missing = {}
    for i, t in enumerate(toks):
        if t.kind != "name":
            continue
        prev = toks[i - 1] if i > 0 else None
        nxt = toks[i + 1]
        if prev is not None and prev.kind == "op" and prev.value in (".", ":", "::"):
            continue
        if nxt.kind == "op" and nxt.value == "=":
            continue  # table key or assignment target
        if nxt.kind == "op" and nxt.value == ":" and prev is not None and prev.value in ("{", ",", ";"):
            continue  # field name inside a table type
        if t.value in declared or t.value in ROBLOX_GLOBALS:
            continue
        # type annotation contexts: skip names directly after '->' or '<' generic lists
        if prev is not None and prev.value in ("->",):
            continue
        missing.setdefault(t.value, t.line)
    return missing

