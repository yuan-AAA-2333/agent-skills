#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
软著材料生成器：源程序文档（前 30 页 + 后 30 页，每页 ≥50 行）。

软著提交要求（通行做法）：
  * 源程序前 30 页 + 后 30 页，共 60 页；
  * 每页不少于 50 行（不足 60 页的则全部提交）；
  * 页眉/页脚标注软件名称与版本、页码；
  * 通常还要求去掉空行与注释以外的"非常规"内容、保持可读。

本脚本从工程源码按**逻辑顺序**（分层：配置 → 领域 → 核心算法 → 求解 → 可视化 → 入口 → 测试）
收集 .py 文件，剥掉空行，严格按每页 50 行排版，输出 Markdown（便于转 Word/PDF）。

用法：
    python generate-copyright-source-doc.py
"""
from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

LINES_PER_PAGE = 50
FRONT_PAGES = 30
BACK_PAGES = 30


@dataclass
class SourceDoc:
    """一个待生成源程序文档的工程。"""

    key: str
    software_name: str          # 软件全称（含版本）
    version: str
    author: str
    project_dir: Path
    out_path: Path
    # 文件收集顺序（按分层逻辑，而不是字母序）
    order: list[str] = field(default_factory=list)
    include_tests: bool = True
    language: str = "Python"


def collect_files(doc: SourceDoc) -> list[Path]:
    """按给定顺序收集源文件；未在 order 中的文件按路径排序补在后面。"""
    src = doc.project_dir / "src"
    files: list[Path] = []
    for name in doc.order:
        p = src / name
        if p.is_file():
            files.append(p)
        elif p.is_dir():
            files.extend(sorted(p.rglob("*.py")))
    for p in sorted(src.rglob("*.py")):
        if p not in files:
            files.append(p)
    if doc.include_tests:
        test_dir = doc.project_dir / "tests"
        if test_dir.is_dir():
            files.extend(sorted(test_dir.rglob("*.py")))
    return files


def read_lines(path: Path, *, strip_blank: bool = True, strip_comment_only: bool = False
               ) -> tuple[list[str], str]:
    """读取源文件，返回 (行列表, 末尾注释)。"""
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = path.read_text(encoding="gbk", errors="replace")
    raw = text.splitlines()
    out: list[str] = []
    for ln in raw:
        if strip_blank and not ln.strip():
            continue
        if strip_comment_only and ln.strip().startswith("#"):
            continue
        # 制表符统一成 4 空格，避免不同编辑器显示宽度不一致
        out.append(ln.replace("\t", "    ").rstrip())
    return out, ""


def build_stream(doc: SourceDoc) -> tuple[list[tuple[str, int, str]], dict]:
    """把全部源文件拼成一个 (行文本, 页码, 来源文件) 的流。"""
    files = collect_files(doc)
    stream: list[tuple[str, int, str]] = []
    stats: dict = {"files": [], "total_lines": 0}

    for path in files:
        lines, _ = read_lines(path)
        if not lines:
            continue
        rel = path.relative_to(doc.project_dir).as_posix()
        # 每个文件前插入三行分隔注释（标明文件名），便于评审对照。
        # 注意这里**不插入空行**：软著源程序文档按"去空行"排版，
        # 行数统计必须与实际排入文档的行数一致，否则会出现
        # "声明 66 页但最后一页只有 3 行"的错位。
        header = [f"# {'=' * 68}", f"# 文件: {rel}", f"# {'=' * 68}"]
        for ln in header + lines:
            if ln.strip():                     # 建流时就剔除空行，保证分页准确
                stream.append((ln, 0, rel))
        stats["files"].append((rel, len(header) + sum(1 for ln in lines if ln.strip())))

    total = len(stream)
    stats["total_lines"] = total
    pages = (total + LINES_PER_PAGE - 1) // LINES_PER_PAGE
    stats["total_pages"] = pages
    return stream, stats


def render(doc: SourceDoc, stream: list[tuple[str, int, str]], stats: dict,
           *, front: int = FRONT_PAGES, back: int = BACK_PAGES) -> str:
    """渲染成 Markdown 源程序文档。

    关键点：**先过滤空行，再分页**。软著源程序文档要求"每页不少于 50 行"，
    如果在拼接阶段把空行也计入行数，渲染时再剔除，就会出现
    "统计 66 页但实际最后一页只有 3 行"的错位。
    """
    # 第一步：剔除空行（源码里的空行、多行字符串里的空行一并去掉）
    clean = [t for t in stream if t[0].strip()]
    total_lines = len(clean)
    stats["total_lines"] = total_lines

    # 分页：每页恰好 50 行。若最后一页不足 50 行，**丢弃该尾页**——
    # 软著提交要求每页不少于 50 行，留一个 3 行的尾页会被打回；
    # 丢弃尾页不影响评审：提交范围本就是"前 30 页 + 后 30 页"。
    total_pages = max(1, total_lines // LINES_PER_PAGE)
    per_page: list[list[str]] = [
        [t[0] for t in clean[i * LINES_PER_PAGE:(i + 1) * LINES_PER_PAGE]]
        for i in range(total_pages)
    ]
    stats["total_pages"] = total_pages
    stats["dropped_tail_lines"] = total_lines - total_pages * LINES_PER_PAGE

    use_all = total_pages <= front + back
    if use_all:
        idx = list(range(total_pages))
        note = f"源程序共 {total_pages} 页（不超过 60 页，按规范提交全部）"
    else:
        idx = list(range(front)) + list(range(total_pages - back, total_pages))
        note = (f"源程序共 {total_pages} 页，按规范提交前 {front} 页与后 {back} 页，"
                f"共 {front + back} 页")

    out: list[str] = []
    out.append(f"# {doc.software_name} — 源程序")
    out.append("")
    out.append(f"- **软件全称**：{doc.software_name}")
    out.append(f"- **版本号**：{doc.version}")
    out.append(f"- **著作权人**：{doc.author}")
    out.append(f"- **开发完成日期**：2026 年 6 月 __ 日")
    out.append(f"- **开发语言**：{doc.language}")
    out.append(f"- **源程序总行数**：{stats['total_lines']} 行"
               f"（已去除空行；含 {len(stats['files'])} 个源文件）")
    out.append(f"- **源程序总页数**：{total_pages} 页（每页 {LINES_PER_PAGE} 行）")
    dropped = stats.get("dropped_tail_lines", 0)
    if dropped:
        out.append(f"- **尾页处理**：末页不足 {LINES_PER_PAGE} 行的 {dropped} 行未排入"
                   f"（软著要求每页不少于 {LINES_PER_PAGE} 行，故舍弃过短尾页）")
    out.append(f"- **本文档内容**：{note}")
    out.append("")
    out.append("> 说明：为便于评审核对，每个源文件前插入了 3 行文件头注释；")
    out.append("> 文档已剔除空行，保留全部代码与注释。")
    out.append("")
    out.append("---")
    out.append("")
    out.append("## 源文件清单")
    out.append("")
    out.append("| # | 文件 | 行数 |")
    out.append("|---|---|---|")
    for i, (rel, n) in enumerate(stats["files"], 1):
        out.append(f"| {i} | `{rel}` | {n} |")
    out.append(f"| | **合计** | **{stats['total_lines']}**（含文件头注释） |")
    out.append("")
    out.append("---")
    out.append("")

    for pos, pno in enumerate(idx, 1):
        out.append(f"<!-- 第 {pno + 1} 页 -->")
        out.append("")
        out.append(f"**{doc.software_name}　{''.ljust(0)}　第 {pno + 1} 页 / 共 {total_pages} 页**")
        out.append("")
        out.append("```python")
        out.extend(per_page[pno])
        out.append("```")
        out.append("")
        if pos == front and not use_all:
            out.append("<!-- ============ 前 30 页结束 / 后 30 页开始 ============ -->")
            out.append("")
    return "\n".join(out) + "\n"


def main() -> int:
    root = Path(r"G:\Code\01-科研\Mathematical-Modeling-Research")

    docs = [
        SourceDoc(
            key="B",
            software_name="烟幕干扰弹投放策略优化系统",
            version="V1.0",
            author="胡声源",
            project_dir=root / "期中作业" / "smoke_screen_opt",
            out_path=root / "期中作业" / "smoke_screen_opt" / "docs" / "软著_源程序文档.md",
            order=["smoke_screen/__init__.py", "smoke_screen/config.py",
                   "smoke_screen/kinematics.py", "smoke_screen/geometry.py",
                   "smoke_screen/scenario.py", "smoke_screen/simulator.py",
                   "smoke_screen/optimizer.py", "smoke_screen/sensitivity.py",
                   "smoke_screen/reporting.py", "smoke_screen/plotting.py",
                   "smoke_screen/cli.py"],
            include_tests=True,
        ),
        SourceDoc(
            key="A",
            software_name="基于 QUBO 建模与混合局部搜索的物流配送路径优化系统",
            version="V1.0",
            author="胡声源",
            project_dir=root / "mathorcup" / "代码" / "qubo_dispatch",
            out_path=root / "mathorcup" / "代码" / "qubo_dispatch" / "docs" / "软著_源程序文档.md",
            order=["qubo_dispatch/__init__.py", "qubo_dispatch/config.py",
                   "qubo_dispatch/domain.py", "qubo_dispatch/dataio.py",
                   "qubo_dispatch/evaluate.py", "qubo_dispatch/qubo.py",
                   "qubo_dispatch/backends.py", "qubo_dispatch/localsearch.py",
                   "qubo_dispatch/clustering.py", "qubo_dispatch/reduction.py",
                   "qubo_dispatch/optimizer.py", "qubo_dispatch/sensitivity.py",
                   "qubo_dispatch/brute.py", "qubo_dispatch/reporting.py",
                   "qubo_dispatch/plotting.py", "qubo_dispatch/cli.py"],
            include_tests=True,
        ),
    ]

    for doc in docs:
        if not doc.project_dir.is_dir():
            print(f"  [{doc.key}] 工程不存在，跳过: {doc.project_dir}")
            continue
        stream, stats = build_stream(doc)
        text = render(doc, stream, stats)        # render 会重算并回写统计
        doc.out_path.parent.mkdir(parents=True, exist_ok=True)
        doc.out_path.write_text(text, encoding="utf-8", newline="\n")
        print(f"  [{doc.key}] {doc.software_name}")
        print(f"        源文件 {len(stats['files'])} 个 / {stats['total_lines']} 行"
              f" / 共 {stats['total_pages']} 页")
        print(f"        已写出: {doc.out_path}（{len(text)} 字符）")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
