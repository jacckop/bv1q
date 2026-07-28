#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TRANSLATIONS = ROOT / "Resources" / "ar.json"
KNOWN = ROOT / "data" / "extracted_whitegram_strings.json"
REPORT = ROOT / "coverage-report.txt"

PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:@|d|ld|lld|u|lu|llu|f|s|%)")


def placeholders(value: str) -> list[str]:
    return sorted(PLACEHOLDER_RE.findall(value))


def main() -> int:
    translations = json.loads(TRANSLATIONS.read_text(encoding="utf-8"))
    known = json.loads(KNOWN.read_text(encoding="utf-8"))

    if not isinstance(known, list) or not all(isinstance(value, str) for value in known):
        raise ValueError(f"{KNOWN} must contain a JSON array of strings")

    missing = [value for value in known if value not in translations]
    empty = [key for key, value in translations.items() if not value.strip()]
    placeholder_errors = [
        key
        for key, value in translations.items()
        if placeholders(key) != placeholders(value)
    ]

    duplicate_casefold: dict[str, list[str]] = {}
    for key in translations:
        duplicate_casefold.setdefault(key.casefold(), []).append(key)
    case_collisions = {
        key: values
        for key, values in duplicate_casefold.items()
        if len(values) > 1 and len({translations[value] for value in values}) > 1
    }

    translated = len(known) - len(missing)
    coverage = (translated / len(known) * 100.0) if known else 100.0

    report = [
        "Whitegram Arabic translation coverage",
        "=====================================",
        f"Known extracted strings: {len(known)}",
        f"Translated strings:      {translated}",
        f"Coverage:                {coverage:.2f}%",
        f"Dictionary entries:      {len(translations)}",
        f"Missing:                 {len(missing)}",
        f"Empty translations:      {len(empty)}",
        f"Placeholder mismatches:  {len(placeholder_errors)}",
        f"Case collisions:         {len(case_collisions)}",
        "",
    ]

    if missing:
        report.append("Missing strings:")
        report.extend(f"- {value!r}" for value in missing)
        report.append("")

    if empty:
        report.append("Empty translations:")
        report.extend(f"- {value!r}" for value in empty)
        report.append("")

    if placeholder_errors:
        report.append("Placeholder mismatches:")
        for key in placeholder_errors:
            report.append(
                f"- {key!r}: source={placeholders(key)} target={placeholders(translations[key])}"
            )
        report.append("")

    if case_collisions:
        report.append("Case-insensitive collisions:")
        for key, values in case_collisions.items():
            report.append(f"- {key}: {values}")
        report.append("")

    REPORT.write_text("\n".join(report) + "\n", encoding="utf-8")
    print(REPORT.read_text(encoding="utf-8"))

    return 1 if missing or empty or placeholder_errors or case_collisions else 0


if __name__ == "__main__":
    sys.exit(main())
