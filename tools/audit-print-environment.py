#!/usr/bin/env python3
"""Verify TransferFields schemas and company/environment storage boundaries."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fields(path):
    return {
        int(number): (name.strip(), kind.strip())
        for number, name, kind in re.findall(
            r"field\((\d+);\s*([^;]+);\s*([^\n]+)\)",
            (ROOT / path).read_text(),
        )
    }


def audit():
    for local, shared, allowed in [
        ("al/src/Setup/Setup.Table.al", "al/src/Print/PrintEnvironment.Table.al",
         {1, 50, 260, 270, 280, 290, 300, 310, 320, 330, 340, 350, 380, 390, 400}),
        ("al/src/Print/Printer.Table.al", "al/src/Print/EnvironmentPrinter.Table.al",
         {1, 2, 4, 5, 6, 7, 8, 10, 17, 18, 19, 20, 21, 22, 23, 24}),
    ]:
        source, target = fields(local), fields(shared)
        mirrored = set(target) & set(source)
        assert mirrored == allowed, (shared, "Unexpected cross-company field", mirrored ^ allowed)
        for number in allowed:
            assert source[number] == target[number], (shared, number, source[number], target[number])
        assert "DataPerCompany = false;" in (ROOT / shared).read_text(), shared
        assert "DataPerCompany = false;" not in (ROOT / local).read_text(), local

    for path in ["al/src/LocalAuth/Terminal.Table.al", "al/src/Print/PrintJobQueue.Table.al"]:
        assert "DataPerCompany = false;" not in (ROOT / path).read_text(), path
    print("PASS: Azure/physical-printer field compatibility and company data boundaries")


if __name__ == "__main__":
    audit()
