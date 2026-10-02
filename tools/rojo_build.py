# -*- coding: utf-8 -*-
"""Rojo-compatible offline STRUCTURE builder (used by unit tests only).

NOT a replacement for the real Rojo: CI always builds the place with the real `rojo build`
(Rojo 7.7.0) and tests/test_rojo_build.py verifies that real build file. This module only mirrors
the instance tree so structural tests can run on machines without Rojo.

Implements the subset of Rojo 7 project semantics that War State uses:
  * default.project.json tree: $className, $path, $properties, $ignoreUnknownInstances, children
  * directories -> Folder, *.server.luau -> Script, *.client.luau -> LocalScript,
    *.luau -> ModuleScript, *.json -> ModuleScript returning the decoded table (like Rojo),
    *.model.json -> instance tree (ClassName / Children; properties are not serialized here),
    init*.luau files turn their folder into that script, dot-files are ignored
  * duplicate instance names inside one parent are reported as errors (Rojo refuses them)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from xml.sax.saxutils import escape

SCRIPT_SUFFIXES = (
    (".server.luau", "Script"),
    (".client.luau", "LocalScript"),
    (".server.lua", "Script"),
    (".client.lua", "LocalScript"),
    (".luau", "ModuleScript"),
    (".lua", "ModuleScript"),
)


class RojoError(Exception):
    pass


class Node:
    def __init__(self, class_name, name, source=None, properties=None):
        self.class_name = class_name
        self.name = name
        self.source = source
        self.properties = properties or {}
        self.children = []

    def add(self, child, allow_duplicates=False):
        if not allow_duplicates:
            for other in self.children:
                if other.name == child.name:
                    raise RojoError("Duplicate instance name '%s' under '%s'" % (child.name, self.name))
        self.children.append(child)

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def lua_literal(value, indent=0):
    pad = "\t" * (indent + 1)
    end = "\t" * indent
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        if not value:
            return "{}"
        return "{\n" + "".join(pad + lua_literal(v, indent + 1) + ",\n" for v in value) + end + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        parts = []
        for k, v in value.items():
            key = k if k.isidentifier() else "[%s]" % json.dumps(k, ensure_ascii=False)
            parts.append(pad + key + " = " + lua_literal(v, indent + 1) + ",\n")
        return "{\n" + "".join(parts) + end + "}"
    raise RojoError("Unsupported JSON value %r" % (value,))


def script_class(path: Path):
    for suffix, cls in SCRIPT_SUFFIXES:
        if path.name.endswith(suffix):
            return cls, path.name[: -len(suffix)]
    return None, None


def model_node(data: dict, name: str) -> Node:
    node = Node(data.get("ClassName", "Folder"), name)
    for child in data.get("Children", []):
        # Inside .model.json files Roblox allows duplicate names (e.g. many "Tree" models).
        node.add(model_node(child, child.get("Name", child.get("ClassName", "Instance"))), allow_duplicates=True)
    return node


def node_from_path(path: Path, name: str | None = None) -> Node | None:
    if path.is_dir():
        init = None
        for candidate in ("init.server.luau", "init.client.luau", "init.luau"):
            if (path / candidate).is_file():
                init = path / candidate
                break
        if init:
            cls, _ = script_class(init)
            node = Node(cls, name or path.name, init.read_text(encoding="utf-8"))
        else:
            node = Node("Folder", name or path.name)
        for child in sorted(path.iterdir()):
            if child.name.startswith(".") or child == init:
                continue
            sub = node_from_path(child)
            if sub is not None:
                node.add(sub)
        return node
    cls, base = script_class(path)
    if cls:
        return Node(cls, name or base, path.read_text(encoding="utf-8"))
    if path.name.endswith(".model.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        return model_node(data, name or path.name[: -len(".model.json")])
    if path.name.endswith(".json") and not path.name.endswith(".project.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        return Node("ModuleScript", name or path.name[:-5], "return " + lua_literal(data) + "\n")
    return None  # unknown file types are ignored


def node_from_tree(name: str, tree: dict, root: Path) -> Node:
    if "$path" in tree:
        target = root / tree["$path"]
        if not target.exists():
            raise RojoError("$path does not exist: %s" % tree["$path"])
        node = node_from_path(target, name)
        if "$className" in tree:
            node.class_name = tree["$className"]
    else:
        node = Node(tree.get("$className", "Folder"), name)
    node.properties.update(tree.get("$properties", {}))
    for key, value in tree.items():
        if key.startswith("$"):
            continue
        node.add(node_from_tree(key, value, root))
    return node


def load_project(project_file: Path) -> Node:
    project = json.loads(project_file.read_text(encoding="utf-8"))
    return node_from_tree(project.get("name", "Place"), project["tree"], project_file.parent)


_ref = [0]


def _xml_item(node: Node, out: list, depth: int):
    _ref[0] += 1
    ind = "  " * depth
    out.append('%s<Item class="%s" referent="RBX%08X">' % (ind, node.class_name, _ref[0]))
    out.append("%s  <Properties>" % ind)
    out.append('%s    <string name="Name">%s</string>' % (ind, escape(node.name)))
    if node.source is not None:
        if "]]>" in node.source:
            raise RojoError("Source of %s contains ']]>'" % node.name)
        out.append('%s    <ProtectedString name="Source"><![CDATA[%s]]></ProtectedString>' % (ind, node.source))
    for key, value in node.properties.items():
        if isinstance(value, bool):
            out.append('%s    <bool name="%s">%s</bool>' % (ind, key, "true" if value else "false"))
        elif isinstance(value, (int, float)):
            out.append('%s    <double name="%s">%s</double>' % (ind, key, value))
        elif isinstance(value, str):
            out.append('%s    <string name="%s">%s</string>' % (ind, key, escape(value)))
    out.append("%s  </Properties>" % ind)
    for child in node.children:
        _xml_item(child, out, depth + 1)
    out.append("%s</Item>" % ind)


def build_place(project_file: Path, output: Path) -> dict:
    root = load_project(project_file)
    if root.class_name != "DataModel":
        raise RojoError("Project root must be a DataModel")
    _ref[0] = 0
    out = ['<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">']
    for service in root.children:
        _xml_item(service, out, 1)
    out.append("</roblox>")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(out) + "\n", encoding="utf-8")
    counts = {}
    for node in root.walk():
        counts[node.class_name] = counts.get(node.class_name, 0) + 1
    return {"output": str(output), "instances": sum(counts.values()), "classes": counts, "root": root}


def instance_paths(root: Node):
    """Yields 'Service/Child/...' paths."""
    def rec(node, prefix):
        for child in node.children:
            path = child.name if not prefix else prefix + "/" + child.name
            yield path
            yield from rec(child, path)
    yield from rec(root, "")


if __name__ == "__main__":
    project = Path(sys.argv[1] if len(sys.argv) > 1 else "default.project.json")
    target = Path(sys.argv[2] if len(sys.argv) > 2 else "build/structure_check.rbxlx")
    info = build_place(project, target)
    print("Structure check (NOT a real Rojo build) %s (%d instances)" % (info["output"], info["instances"]))
