#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Sanitize hard-coded credentials in migrated code.

- Replaces the real Kaiwu SDK credential with an environment-variable lookup.
- Keeps originals in G:\Code\_origin untouched (read-only reference).
- Writes a report to G:\Code\_credentials_report.md
Run:  python sanitize-credentials.py [--apply]
Without --apply it only reports.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

CODE_ROOT = Path(r"G:\Code")
REPORT = CODE_ROOT / "_credentials_report.md"

# (name, regex, replacement template). Replacement keeps the original line shape
# but reads from the environment instead of embedding the secret.
RULES = [
    (
        "Kaiwu SDK code",
        re.compile(r'KAIWU_SDK_CODE\s*=\s*"([^"]{8,})"'),
        'KAIWU_SDK_CODE = os.environ.get("KAIWU_SDK_CODE", "")',
    ),
    (
        "Kaiwu SDK user id",
        re.compile(r'KAIWU_USER_ID\s*=\s*"([^"]{4,})"'),
        'KAIWU_USER_ID = os.environ.get("KAIWU_USER_ID", "")',
    ),
]

# generic secret patterns worth flagging in the report (never auto-replaced)
FLAG_PATTERNS = [
    ("OpenAI-style key", re.compile(r"sk-[A-Za-z0-9]{16,}")),
    ("bearer token", re.compile(r"Bearer\s+[A-Za-z0-9\-_\.]{20,}")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.")),
    ("password literal", re.compile(r"(?i)\bpassword\s*[:=]\s*[\"'][^\"']{4,}[\"']")),
    ("api key literal", re.compile(r"(?i)\bapi[_-]?key\s*[:=]\s*[\"'][^\"']{8,}[\"']")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]

SKIP_DIR_PARTS = {"_origin", ".git", "node_modules", "__pycache__", ".venv", ".idea"}
TEXT_EXT = {".py", ".ts", ".tsx", ".js", ".jsx", ".json", ".yaml", ".yml", ".md",
            ".txt", ".html", ".css", ".sql", ".ini", ".cfg", ".toml", ".ipynb"}


def iter_files(root: Path):
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if any(part in SKIP_DIR_PARTS for part in p.parts):
            continue
        if p.suffix.lower() not in TEXT_EXT:
            continue
        try:
            if p.stat().st_size > 3_000_000:
                continue
        except OSError:
            continue
        yield p


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="actually rewrite the files")
    args = ap.parse_args()

    replaced: list[tuple[Path, str, int]] = []
    flagged: list[tuple[Path, str, int, str]] = []
    scanned = 0

    for path in iter_files(CODE_ROOT):
        scanned += 1
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue

        original = text
        per_file: dict[str, int] = {}
        for name, rx, repl in RULES:
            text, n = rx.subn(repl, text)
            if n:
                per_file[name] = per_file.get(name, 0) + n
        if text != original:
            replaced.append((path, ", ".join(f"{k}×{v}" for k, v in per_file.items()),
                             sum(per_file.values())))
            if args.apply:
                path.write_text(text, encoding="utf-8", newline="")

        for name, rx in FLAG_PATTERNS:
            m = rx.search(original)
            if m:
                snippet = m.group(0)
                masked = snippet[:6] + "…" + snippet[-4:] if len(snippet) > 12 else "***"
                line_no = original[:m.start()].count("\n") + 1
                flagged.append((path, name, line_no, masked))

    lines = ["# 凭证扫描与消毒报告", "",
             f"- 扫描根目录：`{CODE_ROOT}`",
             f"- 扫描文本文件数：**{scanned}**",
             f"- 模式：{'已实际修改（--apply）' if args.apply else '仅报告（未修改）'}",
             f"- 跳过目录：`_origin`（原始只读副本）、`.git`、`node_modules`、`__pycache__`、`.venv`",
             "",
             "## 1. 硬编码的 Kaiwu SDK 凭证（已改为环境变量）", ""]
    if replaced:
        lines += ["| 文件 | 替换项 | 次数 |", "|---|---|---|"]
        for p, what, n in sorted(replaced, key=lambda x: str(x[0])):
            lines.append(f"| `{p}` | {what} | {n} |")
        lines += ["",
                  "替换后的写法：`KAIWU_SDK_CODE = os.environ.get(\"KAIWU_SDK_CODE\", \"\")`",
                  "",
                  "**运行时需要先设置环境变量**（PowerShell 永久设置）：",
                  "```powershell",
                  "[Environment]::SetEnvironmentVariable('KAIWU_USER_ID','<你的ID>','User')",
                  "[Environment]::SetEnvironmentVariable('KAIWU_SDK_CODE','<你的密钥>','User')",
                  "```",
                  "或临时设置：`$env:KAIWU_SDK_CODE='...'`"]
    else:
        lines.append("未发现。")
    lines += ["", "## 2. 其它疑似敏感串（未自动修改，请人工确认）", ""]
    if flagged:
        lines += ["| 文件 | 类型 | 行号 | 片段（已打码） |", "|---|---|---|---|"]
        for p, name, ln, masked in sorted(flagged, key=lambda x: (str(x[0]), x[2])):
            lines.append(f"| `{p}` | {name} | {ln} | `{masked}` |")
    else:
        lines.append("未发现。")
    lines += ["",
              "## 3. 说明", "",
              "- `G:\\Code\\_origin\\**` 内的原始副本**故意未修改**，以便随时对照；",
              "  如需彻底清除，请在确认新工程可用后自行删除 `_origin` 目录。",
              "- `qsl_os` 的软著申请材料（docx）中也包含同样的凭证文本，若对外提交请一并替换。",
              ""]

    REPORT.write_text("\n".join(lines), encoding="utf-8")
    print(f"scanned={scanned} replaced_files={len(replaced)} flagged={len(flagged)}")
    print(f"report -> {REPORT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
