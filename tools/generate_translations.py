#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Resources" / "ar.json"
OUTPUT = ROOT / "Sources" / "GeneratedTranslations.inc"

def objc_escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )

def main() -> None:
    translations = json.loads(SOURCE.read_text(encoding="utf-8"))
    lines = [
        "static NSDictionary<NSString *, NSString *> *WGGeneratedTranslations(void) {",
        "    return @{",
    ]
    for source, target in sorted(translations.items(), key=lambda item: item[0].casefold()):
        lines.append(f'        @"{objc_escape(source)}": @"{objc_escape(target)}",')
    lines.extend([
        "    };",
        "}",
        "",
    ])
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Generated {OUTPUT.relative_to(ROOT)} with {len(translations)} translations.")

if __name__ == "__main__":
    main()
