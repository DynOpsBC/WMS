#!/usr/bin/env python3
"""Check extension-field compatibility on standard BC posting copy paths.

AL compiles these tables separately; TransferFields only checks matching field
numbers at runtime. Removed fields are skipped by BC; Pending fields are not.
This is a schema check, not a substitute for posting tests against a sandbox.
"""

import re
import sys
from pathlib import Path

PAIRS = (
    ("Warehouse Receipt Header", "Posted Whse. Receipt Header"),
    ("Warehouse Receipt Line", "Posted Whse. Receipt Line"),
    ("Warehouse Shipment Header", "Posted Whse. Shipment Header"),
    ("Warehouse Shipment Line", "Posted Whse. Shipment Line"),
    ("Warehouse Activity Header", "Registered Whse. Activity Hdr."),
    ("Warehouse Activity Line", "Registered Whse. Activity Line"),
    ("Purchase Line", "Purch. Rcpt. Line"),
    ("Sales Line", "Sales Shipment Line"),
    ("Warehouse Journal Line", "Warehouse Entry"),
)


def fields_by_table(root):
    tables = {}
    for path in sorted(root.rglob("*.al")):
        source = path.read_text(encoding="utf-8-sig")
        # Preserve strings while removing comments, so URLs and error texts
        # cannot turn part of a declaration into a comment.
        source = re.sub(
            r"'(?:(?:'')|[^'])*'|//[^\n]*|/\*[\s\S]*?\*/",
            lambda m: m[0] if m[0].startswith("'") else " ", source,
        )
        table = re.search(r'tableextension\s+\d+\s+"[^"]+"\s+extends\s+("[^"]+"|\w+)', source, re.I)
        if not table:
            continue
        fields = tables.setdefault(table[1].strip('"'), {})
        declarations = list(re.finditer(r'\bfield\(\s*(\d+)\s*;\s*("[^"]+"|\w+)\s*;\s*([^\)]+)\)', source, re.I))
        for index, match in enumerate(declarations):
            end = declarations[index + 1].start() if index + 1 < len(declarations) else len(source)
            body = source[match.end():end]
            if re.search(r'ObsoleteState\s*=\s*Removed\s*;', body, re.I):
                continue
            field_type = re.sub(r'\s+', ' ', match[3].strip()).lower()
            fields[int(match[1])] = (match[2].strip('"'), field_type, path)
    return tables


def compatible(source_type, target_type):
    source_text = re.fullmatch(r'(code|text)\[(\d+)\]', source_type)
    target_text = re.fullmatch(r'(code|text)\[(\d+)\]', target_type)
    if source_text and target_text:
        return int(target_text[2]) >= int(source_text[2])
    return source_type == target_type


def audit(root):
    tables = fields_by_table(root)
    failures = []
    for source, target in PAIRS:
        for number in tables.get(source, {}).keys() & tables.get(target, {}).keys():
            src = tables[source][number]
            dst = tables[target][number]
            if not compatible(src[1], dst[1]):
                failures.append(f"{source}.{src[0]} ({src[1]}) -> {target}.{dst[0]} ({dst[1]}), field {number}")
    for failure in failures:
        print(f"FAIL TransferFields: {failure}")
    if not failures:
        print(f"PASS TransferFields schema: {len(PAIRS)} posting paths checked")
    return bool(failures)


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "al" / "src"
    if not root.is_dir():
        sys.exit(f"AL source directory not found: {root}")
    sys.exit(audit(root))
