#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Second-pass credential sanitizer: handle the multi-line kw.license.init(...) call sites."""
from __future__ import annotations

import re
import sys
from pathlib import Path

CODE_ROOT = Path(r"G:\Code")
SKIP_PARTS = {"_origin", ".git", "node_modules", "__pycache__", ".venv", ".idea"}

PATTERNS = [
    # kw.license.init(user_id="...", sdk_code="...")  (possibly spread over lines)
    (
        re.compile(
            r'kw\.license\.init\(\s*user_id\s*=\s*"([^"]+)"\s*,\s*'
            r'sdk_code\s*=\s*"([^"]+)"\s*\)',
            re.S,
        ),
        'kw.license.init(user_id=os.environ.get("KAIWU_USER_ID", ""),\n'
        '                               sdk_code=os.environ.get("KAIWU_SDK_CODE", ""))',
    ),
]

changed: list[tuple[Path, int]] = []


def main() -> int:
    apply = "--apply" in sys.argv
    for path in CODE_ROOT.rglob("*.py"):
        if any(p in SKIP_PARTS for p in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        original = text
        total = 0
        for rx, repl in PATTERNS:
            text, n = rx.subn(repl, text)
            total += n
        if text == original or total == 0:
            continue
        # make sure "import os" exists at module level
        if not re.search(r"(?m)^\s*import os\b", text):
            text = re.sub(r"(?m)^(import |from )", "import os\n\\1", text, count=1)
        changed.append((path, total))
        if apply:
            path.write_text(text, encoding="utf-8", newline="")

    for p, n in changed:
        print(f"{'FIXED' if apply else 'WOULD FIX'} {n}x  {p}")
    print(f"files={len(changed)} apply={apply}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
