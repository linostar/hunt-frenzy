#!/usr/bin/env python3
"""Tells validate.sh whether the Godot import cache is stale, by Godot's own rule.

A checkout's import cache (huntfrenzy/.godot/imported/) is stale when a tracked asset (a file
with a committed .import beside it) has not been imported yet (a dest_files entry of its
.import is missing, or the .md5 record Godot keeps beside them is), or when its content has
changed since its import (its md5 is not the source_md5 Godot recorded). Only content counts,
as for Godot itself: a file that was only touched (a newer mtime, the same bytes) is not
stale, and Godot does not rewrite its import then, so an mtime rule would stay stale forever.
validate.sh runs the tolerant priming import when this says stale.

Standard library only.

Usage (from repo root):
    python3 tools/import_cache.py <project dir>   prints "stale: <why>" or "fresh"; exit 0
                                                  (2 on an unreadable .import or record)
    python3 tools/import_cache.py --self-test     checks each rule on small made-up projects;
                                                  prints "import_cache: OK (N cases)"
"""
import hashlib
import os
import re
import sys
import tempfile
from pathlib import Path

DEST_FILES = re.compile(r"^dest_files=\[(.*)\]$", re.MULTILINE)
SOURCE_MD5 = re.compile(r'^source_md5="([0-9a-f]{32})"$', re.MULTILINE)


class CacheError(Exception):
    pass


def res_path(project, res):
    """The file a res:// path names inside `project`."""
    return project / res.removeprefix("res://")


def record_of(dest):
    """Godot's .md5 record of an import: beside its first dest file, extension .md5."""
    return dest.with_suffix(".md5")


def stale_reason(project):
    """Why `project`'s import cache is stale, or None when every asset's import is current."""
    imported = project / ".godot" / "imported"
    if not imported.is_dir():
        return "no import cache"
    imports = sorted(p for p in project.rglob("*.import") if ".godot" not in p.relative_to(project).parts)
    for import_file in imports:
        source = import_file.with_suffix("")
        if not source.is_file():
            continue
        name = source.relative_to(project).as_posix()
        try:
            text = import_file.read_text(encoding="utf-8")
        except OSError as e:
            raise CacheError(f"cannot read {import_file}: {e}")
        found = DEST_FILES.search(text)
        if found is None:
            continue
        dests = [res_path(project, d) for d in re.findall(r'"(res://[^"]+)"', found.group(1))]
        if not dests:
            continue
        for dest in dests:
            if not dest.is_file():
                return f"{name} is not imported yet"
        record = record_of(dests[0])
        if not record.is_file():
            return f"{name} is not imported yet (no {record.name})"
        try:
            recorded = SOURCE_MD5.search(record.read_text(encoding="utf-8"))
        except OSError as e:
            raise CacheError(f"cannot read {record}: {e}")
        if recorded is None:
            raise CacheError(f"{record} has no source_md5")
        if hashlib.md5(source.read_bytes()).hexdigest() != recorded.group(1):
            return f"{name} changed since its import"
    return None


def make_project(root, content=b"<svg/>", imported=True, record=True):
    """A one-asset project under `root` (art/a.svg with its .import), imported as Godot does
    (dest file plus .md5 record) unless told otherwise; returns the source path."""
    (root / "art").mkdir(parents=True)
    source = root / "art" / "a.svg"
    source.write_bytes(content)
    dest = "res://.godot/imported/a.svg-0123456789abcdef0123456789abcdef.ctex"
    (root / "art" / "a.svg.import").write_text(f'[remap]\n\n[deps]\n\nsource_file="res://art/a.svg"\ndest_files=["{dest}"]\n')
    (root / ".godot" / "imported").mkdir(parents=True)
    if imported:
        res_path(root, dest).write_bytes(b"texture")
    if record:
        record_of(res_path(root, dest)).write_text(f'source_md5="{hashlib.md5(content).hexdigest()}"\ndest_md5="0"\n')
    return source


def self_test():
    """Each rule on a made-up project: (name, setup(root), expected reason or None)."""
    def no_cache(root):
        make_project(root)
        for f in sorted((root / ".godot").rglob("*"), reverse=True):
            f.unlink() if f.is_file() else f.rmdir()
        (root / ".godot").rmdir()

    def changed(root):
        make_project(root).write_bytes(b"<svg>changed</svg>")

    def touched(root):
        source = make_project(root)
        later = source.stat().st_mtime + 3600
        os.utime(source, (later, later))

    def not_imported(root):
        make_project(root, imported=False)

    def no_record(root):
        make_project(root, record=False)

    def orphan_import(root):
        make_project(root).unlink()

    cases = [
        ("a fresh cache is not stale", make_project, None),
        ("no cache is stale", no_cache, "no import cache"),
        ("a missing imported file is stale", not_imported, "art/a.svg is not imported yet"),
        ("a missing import record is stale", no_record, "art/a.svg is not imported yet (no a.svg-0123456789abcdef0123456789abcdef.md5)"),
        ("changed content is stale", changed, "art/a.svg changed since its import"),
        ("a touch that keeps the content is not stale", touched, None),
        ("an .import without its asset is ignored", orphan_import, None),
    ]
    failures = []
    for name, setup, expected in cases:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            setup(root)
            got = stale_reason(root)
        if got != expected:
            failures.append(f"{name}: got {got!r}, expected {expected!r}")
    if failures:
        raise CacheError("self-test failed:\n" + "\n".join(failures))
    print(f"import_cache: OK ({len(cases)} cases)")


def main():
    try:
        if sys.argv[1:] == ["--self-test"]:
            self_test()
        elif len(sys.argv) == 2 and not sys.argv[1].startswith("-"):
            reason = stale_reason(Path(sys.argv[1]))
            print(f"stale: {reason}" if reason is not None else "fresh")
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except CacheError as e:
        print(f"import_cache: error: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
