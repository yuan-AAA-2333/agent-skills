# agent-skills

Reusable **skills** for AI coding agents, distilled from real sessions on Windows machines behind
Chinese campus/mobile networks.

Each skill is a single `SKILL.md` with YAML frontmatter (`name` + `description`). The `description` is
what an agent matches on to decide whether to load it, so it states the *situations*, not just the topic.

## Contents

| Skill | Load it when… | What's inside |
|---|---|---|
| [`windows-china-network-traps`](windows-china-network-traps/SKILL.md) | A download, install or network request hangs, stalls or fails — winget/pip/npm/git appearing frozen, Docker pulls failing, installers timing out, PowerShell scripts refusing to run. | Telling "hang" from "slow" with the right evidence per tool; IPv4-vs-IPv6 routing; DNS-poisoning fingerprints; Docker registry mirrors and daemon hardening; winget source/PATH traps; verifying a downloaded installer; nine Windows PowerShell 5.1 scripting traps; ACL-vs-long-path diagnosis; handing over self-elevating scripts. |
| [`windows-machine-dossier`](windows-machine-dossier/SKILL.md) | Surveying, documenting or inventorying a Windows machine, refreshing a machine README that other agents read, or planning a safe cleanup. | Read-only survey workflow; parallel per-domain subagents; the **verify-before-write** rule; the `AGENTS.md` output contract; linting the deliverable (paths, secrets, markdown, encoding, stale claims); manifest-before-delete cleanup discipline. |
| [`windows-bulk-relocation`](windows-bulk-relocation/SKILL.md) | Moving applications, data directories, caches or whole code trees to another drive while everything must keep working; relocating an agent's own runtime data; consolidating scattered projects; reclaiming space on `C:`. | The `copy → per-file verify → rename source → junction` pattern (never cut-paste); why a file count is not a verification; robocopy `/MOVE` skip traps; hardlink double-counting by inode; junction hygiene (case-aliased paths, `islink` vs `isjunction`, chains, the 11 OS compatibility junctions); what must never be moved; self-elevating handover scripts. |
| [`refactor-verified-against-reference`](refactor-verified-against-reference/SKILL.md) | Restructuring code that already works and whose numbers must not change; turning research scripts into a configurable package; merging duplicated implementations that drifted; producing handover/copyright deliverables from throwaway code. | Read-only original + snapshot; extracting the single source of truth for the objective; the line-by-line reference cross-check to bit-equality; decimal-literal precision loss; adapter + fallback instead of a hard dependency; constraining parallel subagents then cross-auditing them; recording what was *not* verified. |
| [`numerical-optimization-bug-patterns`](numerical-optimization-bug-patterns/SKILL.md) | A numerical, geometric or combinatorial optimiser silently returns wrong or degenerate results; a penalty formulation prefers infeasible solutions; a later stage makes the answer worse; a derivation keeps contradicting what the code prints. | Eight named defects that run without erroring (monotone-stage assumption, dropped constraint constant, wrong diagonal sign, sentinel-crossing index bounds, non-bijective decoder, comprehension shadowing, divergence-as-arrival, coordinate-convention physics); the brute-force ground-truth harness; the least-one-violation probe; "never tune a coefficient to pass a test". |
| [`chinese-software-copyright-package`](chinese-software-copyright-package/SKILL.md) | Preparing a 软著 filing from an existing codebase — the 60-page source listing (前30页+后30页), the software manual, or the checklist of what the applicant must still supply. | The page/line-count rules the registry enforces; three pagination mistakes that cost iterations; per-page verification by re-parsing the output; manual structure and screenshot placeholders; the fields that must never be invented; how to pre-empt the "two similar filings" question. |

## Installing

Drop a skill directory into any root your agent harness scans for skills. For DeepSeek Harness that is
typically `%USERPROFILE%\.dsh\skills\` (user-level), `<project>\.dsh\skills\` (project-level), or
`%USERPROFILE%\.agents\skills\`:

```powershell
git clone https://github.com/yuan-AAA-2333/agent-skills.git
Copy-Item -Recurse .\agent-skills\*\ "$env:USERPROFILE\.dsh\skills\"
```

Most harnesses pick new skills up without a restart.

> ⚠️ If you have edited the installed copies, do not blindly re-copy: compare first
> (`Get-FileHash`) and merge — the installed copy can legitimately be *newer* than the repo.

## Why these are worth reading

Almost every rule here was learned by getting it wrong first, and each one is written with the evidence
that settled it:

- **"winget is hung"** — it wasn't. winget delegates the download to the DeliveryOptimization service, so
  the winget process can show *zero* TCP connections and an empty temp directory while a 604 MB download
  runs at full speed. Judging it by those two signals got a working install killed at ~85%. The only
  trustworthy source is winget's own log.
- **"IPv4 doesn't work here"** — the answer *flipped twice within one session* as the active link changed
  between a campus WLAN and a USB-tethered phone. Test both families every time; never hardcode the verdict.
- **`Face:b00c`** — a DNS answer in Meta's `2a03:2880::/32` range for `registry-1.docker.io`, complete with
  the `face:b00c` poisoning fingerprint. Docker's own error text blames "no HTTPS proxy", which is a
  misleading template — chasing a proxy is a dead end.
- **`sc config …`** — `sc` is a PowerShell alias for `Set-Content`, so the real `sc.exe` is never invoked
  and the command fails at parameter binding: it does *nothing*. Every pasted instruction must carry the
  fix, which is why these skills hand over self-elevating scripts instead of command blocks.
- **"`robocopy /MOVE` succeeded"** — it exited 1 (success) while silently skipping a pnpm symlink tree:
  7,796 files / 319.7 MB never arrived and the source had already been deleted. A file *count* also lied
  twice more in the same session (`Get-ChildItem -Recurse` counted one directory as 31 files and as
  25,379 files; hardlinked conda packages inflated 11.45 GB to 17.08 GB). Verify by relative path + byte
  size, and de-duplicate by inode before quoting any size.
- **"the relaxation is the objective"** — it isn't. A QUBO linearisation scored a solution at energy 5.0
  that the true cost function scored at 16.0, and the formulation's diagonal sign was inverted so
  "do nothing" beat every feasible plan. Both were found by a three-case energy probe and a brute-force
  ground truth — not by reading the code.
- **"the last page is fine"** — a 3-line final page in a 65-page source listing gets a 软著 filing
  rejected. The registry wants ≥50 lines on *every* page.

## License

No license file yet — add one if you intend to reuse this. Until then, default copyright applies.
