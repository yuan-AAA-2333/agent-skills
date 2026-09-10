---
name: windows-machine-dossier
description: Use when asked to survey, document, profile, or inventory a Windows machine — building or refreshing a machine dossier / README that other AI agents read, taking stock of installed software, toolchains, environment variables, services or disks, mapping directory structure and disk usage, or planning a safe cleanup of caches and leftovers. Covers the read-only survey workflow, the verify-before-write rule, the AGENTS.md output contract, and non-destructive deletion practice.
---

# Building and maintaining a Windows machine dossier

The deliverable is a single Markdown file that other agents read so they stop re-discovering the machine. Two things make it valuable: **every fact is verified on the machine**, and **one file, at a stable location**.

## Output contract

- **Location:** `%USERPROFILE%\AGENTS.md` — the user's home directory. Agents that read a home-level `AGENTS.md` pick it up automatically.
- **Format:** one UTF-8 file **without BOM**, LF line endings, GitHub-flavoured Markdown. Write the prose in the user's own language; keep identifiers in English.
- **Shape:** §0 TL;DR → §1 conventions/red lines → §2 hardware → §3 disk map → §4 toolchains → §5 package managers → §6 software inventory → §7 agent ecosystem → §8 system config (env/PATH/ports/services) → §9 DB/WSL/VM → §10 project index → §11 pitfalls → appendices (raw data, method, change log).
- **Length is fine.** One instance reached ~1200 lines. Agents skim §0 and jump; completeness beats brevity here — but keep §0 genuinely skimmable and let the rest be navigable by headings.

## Red lines (non-negotiable)

- **Read-only by default.** No installs, no registry writes, no service changes, no deletions during a survey.
- **Never capture a credential value.** API keys, tokens, passwords, private keys, licence keys, cookies, `auth.json`, `.credentials.yaml`, browser `Login Data`: record *existence, path, and key names* only. Not one character of value.
- **Privacy directories get "exists + size" only** — chat archives, `Desktop`/`Documents`/`Pictures`, browser profiles, cloud-sync folders. Count bytes; never read contents.
- Say so explicitly in the dossier: include a section listing which paths agents must not traverse.

## Phase 1 — Cheap probes before anything expensive

Get the shape of the machine in seconds: `Get-Volume` for drives, `Win32_ComputerSystem` / `Win32_Processor` / `Win32_VideoController` for hardware, `nvidia-smi` for GPU, top-level listings of each drive. This is also the moment to **learn what the user actually cares about** — which drives matter, which account is in use, which agent tooling is already installed.

## Phase 2 — Parallel survey, one subagent per domain

Four domains work well: toolchains, installed software, system config, AI-agent ecosystem. Give each subagent a **self-contained** prompt (they do not see your conversation) containing:

- the machine facts you already measured;
- an explicit read-only constraint (no install/update/download; `winget list` is fine, `winget export` is not);
- the credential and privacy rules above;
- a raw-output path (e.g. `<survey-dir>\raw\NN-topic.md`) and a **≤120-line report back**, not a copy of the raw file;
- a reminder of the shell's real capabilities (on Windows that often means PowerShell **5.1** with no `pwsh`, and no elevation).

For the disk map, do not use `Get-ChildItem -Recurse` — on a machine with millions of files it is hopeless. Use a compiled .NET enumerator (`System.IO.DirectoryInfo.EnumerateFileSystemInfos`) driven by an explicit stack, skipping reparse points, tolerating `UnauthorizedAccessException`, and recording subtree file counts and byte totals per directory down to a depth limit.

## Phase 3 — Verify every claim before it enters the dossier (the important rule)

**Subagent reports contain errors. Two of them reached a near-final draft in the session these notes come from:**

1. "MATLAB is installed twice, at `E:\MATLAB` and `E:\Matlab`" — those are **the same directory**; Windows paths are case-insensitive and the registry merely cased it differently. One `Get-Item` comparison plus the recorded directory listing disproved it.
2. ".NET SDK 10.0.5 is installed" — the machine had **only runtimes**; `dotnet --list-sdks` returned `No SDKs were found.` The agent had read the host version and called it an SDK.

So, before writing:

- **Re-measure anything a decision could hinge on.** Run the version command yourself; `Test-Path` the paths.
- **Sweep every path mentioned in the draft** with one `Test-Path` loop — a few dozen paths take seconds and catch typos and stale claims.
- **Distrust "two copies" / "duplicate install" claims** until you compare identity, not path strings.
- **Prefer WMI over the DISM cmdlets for non-elevated queries** — e.g. `Get-CimInstance Win32_OptionalFeature` works where `Get-WindowsOptionalFeature` demands admin.
- When raw data and a summary disagree, the raw data wins — but re-run it.

## Phase 4 — Write, then lint the deliverable

- **Path sweep** (above).
- **Secret sweep** — regex the finished file for `sk-[A-Za-z0-9]{10,}`, `Bearer\s+\S{10,}`, `eyJ…` JWTs, `password\s*[:=]\s*\S`, `-----BEGIN`. Expect zero hits.
- **Markdown lint** — consistent pipe counts per table row, an even number of ``` fences, no empty headings, no leftover placeholders.
- **Encoding** — LF, no BOM, no `U+FFFD` when decoded as UTF-8.
- **Consistency sweep** — grep for claims you know you superseded (old versions, "not installed" for things you later installed). Stale sentences are the most common defect in a long-lived document.

Careful with incremental edits on a large file: a wrong `old_string` silently merges table rows or deletes a heading. Re-read the region before editing, and re-run the table lint afterwards.

## Phase 5 — Leave a refresh path

Ship a **read-only** refresh script (e.g. `<survey-dir>\Refresh-PC-Profile.ps1`): it re-collects hardware, disks, toolchain versions, installed software, system config, agent ecosystem and a pitfalls self-check, and writes a timestamped report. A `-SkipDiskScan` switch keeps the fast path at ~20 s instead of ~1 min.

Add a **`.cmd` launcher per `.ps1`** so a non-technical user can just double-click it:

```bat
@echo off
rem ASCII only -- cmd.exe decodes .cmd as ANSI/936
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script.ps1" %*
pause
```

## Safe cleanup (only after explicit user authorization)

- **Manifest before delete.** Write every path and byte count to a file first; keep small metadata (file lists, checksums, `.reg` exports, `pip freeze`) in a `backup\` folder so the decision is auditable and partly reversible.
- **Never delete a directory because its name suggests a category.** A folder named like a downloads/installers dump turned out to hold multi-gigabyte personal media and personal documents alongside the installers. Delete by **explicit filename whitelist**, and leave everything else untouched.
- **Prefer reversible actions** for anything ambiguous: back up the `.reg` key before clearing it, snapshot `pip freeze` before an environment upgrade, keep the original config beside the new one.
- **Verify deletions actually happened** (`Test-Path`, re-measure the directory). On Windows PowerShell 5.1 both `Remove-Item` and `Clear-RecycleBin` can fail silently.
- **Report what you deliberately did *not* touch** and why — that is as useful to the user as the list of what you removed.
- Elevation-requiring items cannot be done from a normal shell: hand them over as a **self-elevating script**, not a paste block. See the `windows-china-network-traps` skill for why pasted instructions keep failing where a script would not.
