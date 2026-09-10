# agent-skills

Reusable **skills** for AI coding agents, distilled from real debugging sessions on Windows machines behind Chinese campus/mobile networks.

Each skill is a single `SKILL.md` with YAML frontmatter (`name` + `description`). The `description` is what an agent matches on to decide whether to load it, so it states the *situations*, not just the topic.

## Contents

| Skill | Load it when… | What's inside |
|---|---|---|
| [`windows-china-network-traps`](windows-china-network-traps/SKILL.md) | A download, install or network request hangs, stalls or fails — winget/pip/npm/git appearing frozen, Docker pulls failing, installers timing out, PowerShell scripts refusing to run. | Telling "hang" from "slow" with the right evidence per tool; IPv4-vs-IPv6 routing; DNS-poisoning fingerprints; Docker registry mirrors and daemon hardening; winget source/PATH traps; verifying a downloaded installer; nine Windows PowerShell 5.1 scripting traps; ACL-vs-long-path diagnosis; handing over self-elevating scripts. |
| [`windows-machine-dossier`](windows-machine-dossier/SKILL.md) | Surveying, documenting or inventorying a Windows machine, refreshing a machine README that other agents read, or planning a safe cleanup. | Read-only survey workflow; parallel per-domain subagents; the **verify-before-write** rule; the `AGENTS.md` output contract; linting the deliverable (paths, secrets, markdown, encoding, stale claims); manifest-before-delete cleanup discipline. |

## Installing

Drop a skill directory into any root your agent harness scans for skills. For DeepSeek Harness that is typically `%USERPROFILE%\.dsh\skills\` (user-level), `<project>\.dsh\skills\` (project-level), or `%USERPROFILE%\.agents\skills\`:

```powershell
git clone https://github.com/yuan-AAA-2333/agent-skills.git
Copy-Item -Recurse .\agent-skills\windows-* "$env:USERPROFILE\.dsh\skills\"
```

Most harnesses pick new skills up without a restart.

## Why these are worth reading

Almost every rule here was learned by getting it wrong first, and each one is written with the evidence that settled it:

- **"winget is hung"** — it wasn't. winget delegates the download to the DeliveryOptimization service, so the winget process can show *zero* TCP connections and an empty temp directory while a 604 MB download runs at full speed. Judging it by those two signals got a working install killed at ~85%. The only trustworthy source is winget's own log.
- **"IPv4 doesn't work here"** — the answer *flipped twice within one session* as the active link changed between a campus WLAN and a USB-tethered phone. Test both families every time; never hardcode the verdict.
- **`Face:b00c`** — a DNS answer in Meta's `2a03:2880::/32` range for `registry-1.docker.io`, complete with the `face:b00c` poisoning fingerprint. Docker's own error text blames "no HTTPS proxy", which is a misleading template — chasing a proxy is a dead end.
- **`sc config …`** — `sc` is a PowerShell alias for `Set-Content`, so the real `sc.exe` is never invoked and the command fails at parameter binding: it does *nothing*. Every pasted instruction must carry the fix, which is why these skills hand over self-elevating scripts instead of command blocks.

## License

No license file yet — add one if you intend to reuse this. Until then, default copyright applies.
