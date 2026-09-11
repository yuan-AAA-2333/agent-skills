# Migration & verification scripts

Companion scripts for the `windows-bulk-relocation` and `refactor-verified-against-reference` skills.
Every one of them is a working artifact from a real relocation of ~55 GB across three drives, where
42 junctions were created and every unit was audited file-by-file.

> **These are parameterised by an in-file unit table — edit the paths before running.**
> Paths from the original machine (`C:\Users\76693\…`, `G:\AI\…`) are kept as concrete examples so the
> shape is obvious; replace them with yours. Nothing here is hard-coded to a drive letter beyond that.

## Prerequisites

- **Windows PowerShell 5.1** (no `pwsh` 7 needed).
- Scripts that carry Chinese text are saved **UTF-8 with BOM**; `.cmd` launchers are **ASCII only**
  (cmd.exe decodes `.cmd` as the ANSI codepage and Chinese comments corrupt the line).
- Run with `powershell -NoProfile -ExecutionPolicy Bypass -File <script>.ps1 …`.
- Python 3.10+ on `PATH` for the `.py` helpers (`numpy`/`pandas` only where noted).

## Core relocation loop

| Script | What it does |
|---|---|
| `Move-DataUnit.ps1` | The whole pattern for one unit: **robocopy copy → per-file verify → rename source into `_backup/` → `mklink /J` at the old path**. Idempotent (re-runs skip an already-complete destination), writes a JSONL log per unit, supports `-Mode Copy\|Link\|Cleanup` and `-HashSample N`. |
| `Resume-Migration.ps1` | Re-runs only the units whose source is **not yet a junction** — the resume path after a partial run. |
| `Run-MigrationBatch.ps1` | Runs a named set of units sequentially, one log file for the batch. |
| `Move-CodeUnit.ps1` | Same idea for code trees: **same-volume moves use an atomic rename** (instant, zero copy), cross-volume falls back to robocopy; creates the junction afterwards. |
| `Run-CodeMigration.ps1` | Batch driver for `Move-CodeUnit.ps1`. |

## Verification (run these; do not trust counts)

| Script | What it does |
|---|---|
| `Audit-Migration.ps1` | Walks every relocated unit and compares the live path *through the junction* against its authoritative copy: **missing / extra / size-mismatch per unit**. This is the script that caught a `robocopy /MOVE` that exited 1 (success) while 7,796 files never arrived. |
| `Compare-Tree.ps1` | Generic two-tree diff by relative path + byte size, with CSV output. Use it to answer "is A really a subset of B". |
| `Measure-Tree.ps1` | Fast per-subdirectory and per-extension size report. Compiled .NET enumerator, tolerates access errors, skips reparse points — `Get-ChildItem -Recurse` is unusable on multi-million-file drives. |
| `Get-CodeInventory.ps1` | Read-only scan for project roots by marker files (`.git`, `.idea`, `package.json`, `CMakeLists.txt`, …) across all drives, classified root-vs-subdirectory. |

## Space reclamation

| Script | What it does |
|---|---|
| `Reclaim-More-Space.ps1` | Relocates pure-cache directories (npm/pip/uv caches, VS Code extensions) to another drive **and junctions them back**, so tools keep working with zero reconfiguration. The unit table is the thing to edit. |
| `Fix-Modex-Admin.ps1` + `Run-Fix-Modex.cmd` | **Self-elevating.** For source trees owned by `BUILTIN\Administrators` where the user has only `ReadAndExecute` — those cannot be deleted *or renamed* without elevation. Takes ownership, deletes, creates the junction, re-reads through it to prove it works. |

## Refactor support

| Script | What it does |
|---|---|
| `crosscheck-smoke.py` | The **reference cross-check**: re-implements the original script's formulas line by line (with the original line numbers in comments) and compares outputs over thousands of random parameter sets. Reached `0.000e+00` max difference; prints per-constant alignment and edge/illegal cases. Adapt the two functions at the top. |
| `sanitize-credentials.py`, `sanitize-credentials2.py` | Two-pass secret sweep: pass 1 handles `KEY = "value"` assignments, pass 2 handles multi-line call sites (`client.init(user_id=…, sdk_code=…)`). Reports which files changed and writes a report; `--apply` to actually rewrite. |
| `generate-copyright-source-doc.py` | Builds a Chinese software-copyright source listing: **60 pages (first 30 + last 30), exactly 50 lines per page**, blank lines stripped at stream-build time, partial tail page dropped, per-page header, file index table. See the `chinese-software-copyright-package` skill. |
| `generate-copyright-manual.py` | Drafts the accompanying software manual with explicit screenshot placeholders. |

## Not included (by design)

The one-off scripts that *built* particular packages — `scaffold-*.py`, `fix-a-*.py`,
`make-qslos-cli.py`, `update-progress-a.py`, `write-a-docs.py`, `_final_check.py` — are specific to the
projects they generated and were not kept. `scaffold-*.py` is worth imitating though: each one writes a
whole package (pyproject, configs, modules, tests, docs) from an in-memory dict of file contents, which
makes a large scaffold reviewable as a single readable artifact.

## Safety properties these scripts maintain

- **Nothing is ever deleted before it is verified.** The source is *renamed* into a `_backup/` tree; a
  separate explicit `-Mode Cleanup` step removes backups.
- **A file count is never the verification.** Counts are reported, but the pass/fail decision is per
  relative path + byte size.
- **Reparse points are skipped when measuring**, so junctioned subtrees are not double-counted.
- **Hardlinks are de-duplicated by `(st_dev, st_ino)`** before any size is quoted — hardlinked package
  caches inflated a real 11.45 GB footprint to 17.08 GB.
