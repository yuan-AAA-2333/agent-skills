---
name: chinese-software-copyright-package
description: Use when preparing a Chinese software copyright (软著) filing from an existing codebase — generating the 60-page source listing (前30页+后30页), drafting the software manual, or listing what the applicant still has to supply. Covers the page/line-count rules the registry enforces, why a partial last page gets rejected, blank-line handling, and the fields that must never be invented.
---

# Packaging a codebase for a Chinese software-copyright filing

Two artifacts are produced from the code: a **source listing** (`源程序文档`) and a **manual**
(`软件说明书`). Everything else is applicant data you must not fabricate.

## Output contract

```
<project>/docs/软著_源程序文档.md    ← 60 pages: first 30 + last 30
<project>/docs/软著_软件说明书.md    ← manual draft
<root>/_软著申请材料清单.md          ← checklist of what is done / what the human must supply
```

## Source listing rules (the registry enforces these)

| Rule | Detail |
|---|---|
| **60 pages** | first 30 pages + last 30 pages. If the program is **under 60 pages, submit all of it** and say so. |
| **≥ 50 lines per page** | every page, without exception |
| Header per page | software name + version + `第 N 页 / 共 M 页` |
| Blank lines | **removed** |
| Code and comments | **kept** — do not strip comments to fit a page |
| File order | logical layering (config → domain → core algorithms → solver → visualisation → entry → tests), not alphabetical |
| File separators | a 3-line banner naming each file helps a reviewer follow it |
| Front matter | a table listing every source file with its line count |

### Three mistakes that cost iterations

1. **Counting blank lines, then removing them at render time.** The declared page count was 66 while
   the last page held 3 lines. Strip blanks when you *build* the line stream, and compute totals from
   the stripped stream.
2. **Letting the document header (title table, file list) into the paginated stream.** Same symptom —
   a 3-line tail page, because ~15 header lines were consumed as content.
3. **Leaving the remainder as a short final page.** `3253 = 65×50 + 3` leaves a 3-line page, which is
   rejected. **Drop the partial tail page** and state in the document which lines were omitted — the
   submission only ever uses the first 30 and last 30 pages, so nothing of substance is lost.

Always verify by re-parsing the generated file, per page:

```python
parts = re.split(r"<!-- 第 (\d+) 页 -->", text)
counts = [len(re.findall(r"```python\n(.*?)```", parts[i+1], re.S)[0].rstrip("\n").split("\n"))
          for i in range(1, len(parts), 2)]
assert min(counts) >= 50
```

Markdown → Word/PDF conversion must preserve this: monospace 9–10 pt, A4, moderate margins, then
**re-count the pages in the converted file**.

## Manual rules

Sections that get an application through review: 软件概述（解决什么问题 / 主要功能 / 应用场景）→
运行环境与安装 → 功能模块说明（模块表 + 命令表，与源码结构一致）→ 操作说明（分步，配截图占位）→
算法原理（给出公式）→ 错误处理 → 技术特点小结.

- Mark screenshot slots explicitly: `> 【截图位置 1】场景装配信息输出`. An agent cannot produce runtime
  screenshots — leave the slot, name what belongs there.
- State real measured numbers (test counts, runtimes, quality gaps). Reviewers respond to evidence.

## Fields you must never invent

Collect these from the applicant, and put visible placeholders otherwise:

- **著作权人** (name of the person or organisation)
- **开发完成日期 / 首次发表日期** — a month is not enough for the form; leave `2026 年 6 月 __ 日`
- 身份证号 / 地址 / 电话 / 联系方式 — **never ask for these and never accept them**; the applicant fills
  the form themselves
- Software full name (propose one, let them confirm) and whether a short name is wanted

## Two systems from one applicant: pre-empt the "duplicate" question

If the same person files for several programs, write a short comparison table into the checklist —
problem type, mathematical core, decision variables, algorithms, application domain. Two genuinely
different systems (continuous geometric optimisation vs. discrete combinatorial optimisation) are fine
together; the table is what makes that legible to a reviewer.

## Reusable artifact

`E:\dsh\migration\scripts\generate-copyright-source-doc.py` (stream building, pagination, verification)
and `generate-copyright-manual.py` (manual drafts). Both take a `SourceDoc` describing the project, the
software name, the author and the module ordering.
