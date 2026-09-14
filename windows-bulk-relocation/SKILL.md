---
name: windows-bulk-relocation
description: Use when moving applications, data directories, caches, or whole code trees to another drive on Windows while everything must keep working — relocating an agent's own data, migrating program installs, consolidating scattered projects onto one disk, or reclaiming space on C:. Covers copy→verify→junction (never cut-paste), the audit that catches silent file loss, robocopy /MOVE traps, hardlink double-counting, and the elevation cases that need a self-elevating handover script.
---

# Relocating data on Windows without breaking anything

The deliverable is a relocation where **every old path still resolves** and **every byte is accounted
for**. Two rules make that achievable: never cut-paste, and never trust a file count.

## The pattern

```
copy (robocopy /E /COPY:DAT)  →  per-file verify  →  rename source into _backup/  →  mklink /J at the old path
```

A **directory junction** at the original location means shortcuts, registry `Uninstall` entries,
hardcoded config paths, IDE project files and cron/Task Scheduler jobs all keep working untouched.
The source is *renamed*, never deleted, until verification has passed — that rename is the rollback.

**Never `Move-Item` or cut-paste an application or data directory.** On Windows it breaks hardcoded
absolute paths, and for anything a running process holds open it fails halfway.

## Rule 1 — a file count is not a verification

Three separate ways a count lies, all hit in one session:

| What happened | Why the count lied |
|---|---|
| `robocopy /MOVE` reported success but a pnpm tree was missing 7,796 files / 319.7 MB | `/MOVE` skips symlinked/junction subtrees and still exits 1 (success) |
| `Get-ChildItem -Recurse` counted the same directory as 31 files once and 25,379 files another time | it silently skips directories it cannot traverse |
| A "35 GB of reclaimable cache" estimate was wrong by 12× | `Get-ChildItem … \| Measure-Object Length -Sum` double-counts hardlinks |

**Verify by relative path + byte size, per file.** Not totals, not counts:

```powershell
# Authoritative count: Python os.walk + os.lstat, explicitly skipping reparse points
python -c "
import os
n=s=0
for r,d,f in os.walk(ROOT):
    d[:]=[x for x in d if not os.path.islink(os.path.join(r,x))]
    for x in f:
        try: st=os.lstat(os.path.join(r,x))
        except OSError: continue
        n+=1; s+=st.st_size
print(n, s)"
```

For long-path-sensitive trees, the only safe move is also robocopy:

```powershell
robocopy "$src" "$bk" /MOV /E /R:2 /W:2 /MT:16 /NFL /NDL /NP
# /MOV not /MOVE — moves files, then delete the empty skeleton yourself:
python -c "import os; os.system('')" # or .NET:
#   [System.IO.Directory]::Delete('\\?\' + $src, $true)
```

`Move-Item` throws `PathTooLongException` past 260 chars; `.NET Directory::Delete` needs the `\\?\` prefix.

## Rule 2 — hardlinks inflate every "size" number

`conda`'s `pkgs/` shares hardlinks with `envs/`. A naive walk reported **17.08 GB** where the real
footprint was **11.45 GB** (33% double-counted). Aggregate by inode before quoting a size:

```python
seen = {}
for ...: seen.setdefault((st.st_dev, st.st_ino), st.st_size)
real = sum(seen.values())
```

Corollary: "clean A and you free B" conclusions are wrong when A and B share inodes. Check before
promising space. Estimated 35 GB reclaimable; `conda clean -a` actually freed **3.02 GB**.

## Rule 3 — junction hygiene

- **Junctions outlive case-insensitive path aliasing.** `G:\code` and `G:\Code` are the *same*
  directory; deleting the "other" one deletes your junction. Verify with
  `Get-Item -Force | Select Target` (and `ReparsePoint` in `Attributes`), not by path string.
- **Python's `os.path.islink()` returns False for junctions** — it only sees symlinks. Use
  `os.path.isjunction()` (3.12+) or shell out to PowerShell. A junction-health audit built on
  `islink` reports every healthy junction as broken.
- **Windows ships 11 compatibility junctions** in `%USERPROFILE%` (`Application Data`, `My Documents`,
  `Cookies`, `Local Settings`…). They have no `Target` readable via `.Target`; they are not yours and
  a `.Target`-based audit will flag them as broken. Exclude them.
- **Junction chains form silently.** If a target is itself a junction you get a two-hop chain. Collapse
  it: `rmdir` the link (never the target), then `mklink /J` straight to the real directory.
- **Segregate what must not move**: databases in use (SQLite `-wal`/`-shm`), MySQL data dirs, browser
  profiles, and the runtime a live process is executing from. Copy-and-link is right for these; move is not.

## Rule 4 — the process you are running inside is not movable

A DSH/agent session executing from `…\npm-cache\_npx\<hash>\` cannot relocate that directory: open file
handles cause `ERROR 5` on delete and the session would be severed. Detect and skip it explicitly —
treat "source is in use" as an expected outcome with a documented alternative, not a failure to retry.

Likewise, do not relocate an application's data directory when the app is *running*; check first, and
prefer a snapshot copy plus a junction deferred to a quiet moment.

## Rule 5 — elevation is not negotiable, so hand over a script

Files owned by `BUILTIN\Administrators` with only `ReadAndExecute` for the user (common for vendored
`.pak`/`.dll` trees) **cannot be deleted or even renamed** without elevation. `Remove-Item` and
`robocopy` both fail; `rmdir` too. `check owner` first:

```powershell
(Get-Acl -LiteralPath $p).Owner
```

When elevation is needed, ship a **self-elevating `.ps1` plus an ASCII-only `.cmd` launcher** — not a
paste block. `.cmd` must be pure ASCII (cmd.exe decodes it as the ANSI codepage).

## Rule 6 — audit afterwards, and record the exceptions

Ship a reusable audit that walks every relocated unit and compares the live path (through the junction)
against its authoritative copy, reporting `missing` / `extra` / `size-mismatch` per unit. Two legitimate
non-OK verdicts to expect and document rather than "fix":

- the live tree legitimately **grew** (sessions/config written after the snapshot) → `extra > 0`
- the live tree legitimately **grew** (sessions/config written after the snapshot) → `extra > 0`
- the reference is a **subset** (a backup holding data that also contains sibling units)

Finish by recording, in the provenance file: what moved, where the backup is, what was deliberately
**not** touched, and the one-line rollback for each unit (delete junction → rename backup back).

## Reusable artifact

This skill ships its tooling in `scripts/` — 17 parameterised scripts, see `scripts/README.md` for
what each one is for. Highlights: `Move-DataUnit.ps1` (the whole copy→verify→backup→junction
loop), `Audit-Migration.ps1` (the per-file audit), `Reclaim-More-Space.ps1`, `Fix-Modex-Admin.ps1`
(self-elevating). **Edit the in-file unit table before running** — the paths are kept as concrete
examples from the original machine.
