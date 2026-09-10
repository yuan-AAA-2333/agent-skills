---
name: windows-china-network-traps
description: Use when a download, install, or network request hangs, stalls, or fails on Windows — winget / pip / npm / yarn / git clone appearing frozen with no progress, Docker image pulls failing, package installers timing out, "network is slow" complaints that never finish, or PowerShell scripts that refuse to run. Written from Windows machines on Chinese campus and mobile networks; covers IPv4-vs-IPv6 routing, DNS poisoning, registry mirrors, winget source problems, and Windows PowerShell 5.1 scripting traps.
---

# Windows / China network and toolchain traps

These notes come from real debugging sessions on Windows 11 machines behind Chinese campus and mobile networks, with **only Windows PowerShell 5.1** (no `pwsh` 7). Most "slow network" symptoms there are not slow — they are **dead waits that never time out**. Diagnose the failure mode before touching any configuration.

## Rule 0 — Distinguish "hang" from "slow" — with the right evidence for the right tool

Never retry, and never re-download, before you know which one it is. **The signals differ per tool, and using the wrong one produces a confident, wrong, and destructive verdict.**

### The trap that already cost a working install

Judging **winget** by the winget process's own TCP connections, or by `%TEMP%\WinGet`, is invalid:

- winget hands the download to the **DeliveryOptimization service (`DoSvc`, a separate process)**. The winget PID can show **zero TCP connections** while a 604 MB download is progressing at full speed.
- `%TEMP%\WinGet\<Package>\…` is populated **only after** the download finishes — the log line is `Successfully renamed downloaded installer.` Before that the bytes live in DeliveryOptimization's own cache, so the directory looks **empty**.

Observed: `winget install Docker.DockerDesktop` looked completely dead — 8.5 minutes, no progress output, no connections on the winget PID, empty temp dir — and was killed. Its own log showed a 604 MB download running the whole time that **completed at 10m45s and installed successfully**. The kill was wrong; the install finished anyway because `DoSvc` kept working independently.

**So for winget, the only trustworthy signal is winget's own log:**

```powershell
$d = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir"
Get-ChildItem $d -Filter 'WinGet-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
  ForEach-Object { Select-String -LiteralPath $_.FullName -Pattern 'DeliveryOptimization downloading|Download completed|hash verified|Leaf command|Starting:' }
```

- `DeliveryOptimization downloading from url:` … with **no** matching `Download completed.` yet = **still downloading, leave it alone**.
- Also useful: `Get-Service DoSvc` (Running = the real downloader is alive) and, before redoing work, check whether the package already landed (`Get-ItemProperty` on the Uninstall keys).

### Where connection-level checks *are* valid

For downloaders that do their own I/O in-process — `curl`, `pip`, `npm`, `git`, `Invoke-WebRequest`, a browser — these signals are sound:

```powershell
Get-NetTCPConnection -OwningProcess <pid> -ErrorAction SilentlyContinue   # no rows = that process is not transferring
```

Cross-check with the destination: compare the file's `Length` / `LastWriteTime` against the origin's `Content-Length` (`curl -sI <url>`). Two independent signals, or do not call it a stall.

Two more cautions learned the hard way:
- A single 15-second delta is **not** enough to declare a stall. One wrong call killed a 69%-complete 2.7 GB pip download.
- **Prefer `-C -` (resume) over restarting**, always. And after killing anything, check its log/state before redoing the work — it may have completed regardless.

## Rule 1 — Test IPv4 and IPv6 separately, every time — do not assume

**Do not hardcode a verdict about which family works.** Campus and tethered-mobile links differ, and the answer can flip within a single session — one measurement had a campus WLAN active, another an hour later had a USB-tethered phone (an `Ethernet` adapter described as "Remote NDIS based Internet Sharing Device"). In one case IPv4 to international hosts failed while IPv6 ran at ~1 MB/s; later, on a different link, GitHub was reachable over IPv4 and broken over IPv6. **Identify the active adapter first, then measure.**

```powershell
Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed
Get-NetIPAddress -AddressFamily IPv6 |
  Where-Object { $_.PrefixOrigin -ne 'WellKnown' -and $_.IPAddress -notlike 'fe80*' } |
  Select-Object InterfaceAlias,IPAddress,PrefixOrigin
```

Then probe both families against the *same* URL:

```powershell
$u = '<any international url>'
& curl.exe -4 -s -o NUL -w "v4 http=%{http_code} bytes=%{size_download}`n" --max-time 12 -r 0-3000000 $u
& curl.exe -6 -s -o NUL -w "v6 http=%{http_code} bytes=%{size_download}`n" --max-time 12 -r 0-3000000 $u
```

One representative measurement on the Docker installer (`desktop.docker.com`) — stark, and repeatable while that link was active:

| | result |
|---|---|
| IPv4 | **exit 35**, SSL connect error, fails in ~0.25 s |
| IPv6 | **HTTP 206**, ~2 MB in 2.35 s (~950 KB/s) |

**Fix:** download over the working family with resume, then install from the local file.

```powershell
& curl.exe -6 -L -C - --retry 10 --retry-all-errors --retry-delay 3 --connect-timeout 30 -s -o .\pkg.exe "<url>"
```

Note the asymmetry is a property of the **route**, not of the tool: the same `curl.exe` gets both results. A tool that only ever tries one family (winget's DeliveryOptimization path is IPv4-only) can sit at 0% on a URL that `curl -6` fetches at ~1 MB/s — but read Rule 0 before concluding it is stuck: it may simply be slow *and* invisible.

## Rule 2 — Recognize DNS poisoning

A hostile DNS answer looks like an address from an unrelated company's range. Real example: `registry-1.docker.io` resolved to `2a03:2880:f11c:8183:face:b00c:0:25de` — `2a03:2880::/32` is **Meta/Facebook**, and `face:b00c` is a well-known poisoning fingerprint. In the same environment `hub.docker.com` answered with `199.16.158.104`, a **LinkedIn** range. Neither company has anything to do with Docker's registry.

```powershell
Resolve-DnsName <host> -ErrorAction SilentlyContinue | Select-Object Name,IPAddress
```

Suspect poisoning when a host resolves to Meta/Google/Akamai/LinkedIn ranges it has no business using, to `0.0.0.0`/`127.0.0.1`, or when TCP connects but TLS never completes. **Do not try to fix a poisoned host by retrying** — route around it (mirror, the other IP family, or a proxy).

## Rule 3 — Docker Hub needs registry mirrors

When `registry-1.docker.io` is poisoned, direct pulls always fail with `connectex: A connection attempt failed…`. Configure mirrors in `%USERPROFILE%\.docker\daemon.json` (**merge — do not overwrite existing keys** such as `builder`), then **restart**:

```json
{ "registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1panel.live", "https://docker.1ms.run"] }
```
```powershell
& "C:\Program Files\Docker\Docker\resources\bin\docker.exe" desktop restart
& "…\docker.exe" info | Select-String 'Registry Mirrors' -Context 0,4   # verify
```

**Test candidate mirrors before trusting them** — most public ones are dead now. A live registry mirror answers `/v2/` with **401** (or 200):

```powershell
& curl.exe -4 -s -o NUL -w "%{http_code}`n" --max-time 8 "https://<mirror>/v2/"
```

One snapshot (2026-09) — alive: `docker.m.daocloud.io` (401), `docker.1panel.live` (200), `docker.1ms.run` (401). Dead: `docker.mirrors.ustc.edu.cn`, `hub-mirror.c.163.com`, `mirror.baidubce.com`, `dockerhub.icu`, `docker.nju.edu.cn` (403), `registry.dockermirror.com` (525). **Re-test rather than trusting this list** — Chinese mirror availability changes monthly.

**Also harden the daemon's own DNS**, because mirrors do not help when *the daemon itself* has to resolve a poisoned name — the local resolver was handing out fake answers for the whole `docker.io` family:

```json
{ "dns": ["223.5.5.5", "119.29.29.29"] }
```

**Read the error text carefully — it lies.** Docker's message ends with *"…because Docker Desktop has no HTTPS proxy…"* even when no proxy is involved and mirrors are working in the same log. That clause is a fixed template; chasing "configure a proxy" from it is a dead end. The real cause is visible in the address it prints: `2a03:2880:…:face:b00c:…`. The daemon's own log (`%LOCALAPPDATA%\Docker\log\host\httpproxy.log`) has the full request trace if you need proof.

## Rule 4 — winget traps

1. **`msstore` source timeout kills the whole command.** Symptom: `0x80072ee2` (operation timed out) or `0x80072efd` (cannot connect), followed by *"Found the following package in the working source. To continue, specify one of them with the --source option"* (localised) — even though the package obviously exists. **Always pass `--source winget`** for both install and upgrade. `winget source remove msstore` is the permanent fix if nothing is ever installed from the Store via winget.
2. **winget's downloader is single-family and shows no progress.** It can look frozen for ten minutes on a large installer and still be working (see Rule 0). If you want visibility and speed, fetch the installer yourself with `curl -6`, verify it (Rule 5), then run it locally.
3. **A fresh install is not on your PATH yet.** winget writes the *registry*; an already-running process keeps the environment it started with. `Get-Command ffmpeg` returning nothing does not mean the install failed.
   ```powershell
   $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
   ```
   Or call the tool by full path, or look in `%LOCALAPPDATA%\Microsoft\WinGet\Links`.
4. **`winget install` on an already-registered package silently turns into an upgrade** and reports *"No available upgrade found"*. Use `--force` when you really need to re-run an installer (this is how VS BuildTools re-applies its C++ workload, which a plain `winget install` will skip).
5. `winget show --id <id>` reveals the installer URL, size and hash — use it to decide whether to download manually.

## Rule 5 — Verify a downloaded installer before running it

Cheap, and it has already prevented running a truncated file:

```powershell
$f = '.\pkg.exe'
(Get-Item $f).Length                       # compare with: curl.exe -sI <url> | Select-String content-length
[System.IO.File]::ReadAllBytes($f)[0..1]   # 77,90 = "MZ" = valid PE
Get-AuthenticodeSignature $f | Select-Object Status,@{n='Signer';e={$_.SignerCertificate.Subject}}
(Get-FileHash $f -Algorithm SHA256).Hash
```

A size that exactly matches the origin's `Content-Length`, a valid `MZ` header, and `Get-AuthenticodeSignature` reporting **Valid** with the expected publisher is enough to install with confidence.

## Rule 6 — Windows PowerShell 5.1 scripting traps

| Trap | Wrong | Right |
|---|---|---|
| `sc` is an **alias for `Set-Content`** — the real `sc.exe` is never called, and it fails at parameter binding, so it does **nothing at all** | `sc config WSLService start= demand` → `Set-Content : A positional parameter cannot be found that accepts argument 'start='.` | `sc.exe config WSLService start= demand` (keep `.exe` **and** the space after `=`), or the native `Set-Service -Name WSLService -StartupType Manual` |
| Execution policy is effectively **Restricted** | `& .\script.ps1` → *"running scripts is disabled on this system"* | `powershell -NoProfile -ExecutionPolicy Bypass -File ".\script.ps1"` (or `Set-ExecutionPolicy -Scope Process Bypass`) |
| Reading UTF-8 in PS 5.1 without `-Encoding UTF8` mangles text **and swallows newlines** (a 919-line file read as 730 — enough to make a lint pass that should have failed) | `Get-Content f.md` | `Get-Content f.md -Encoding UTF8`, or `[IO.File]::ReadAllText($p,[Text.Encoding]::UTF8)` |
| `.ps1` containing **any non-ASCII** needs a **UTF-8 BOM**, or PS 5.1 decodes it as ANSI and fails to parse | writing the file from a non-PS7 tool | `[IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($true)))` |
| `.cmd` / `.bat` must be **pure ASCII** — cmd decodes them as ANSI/936 and non-ASCII comments corrupt the line (`'启动' is not recognized as an internal or external command`) | non-ASCII `rem` comments | English comments, or put the logic in `.ps1` |
| Console code page is **936**; Python printing emoji / `→` raises `UnicodeEncodeError: 'gbk' codec can't encode character` | `print('✅ done')` | `print('OK done')`, or set `PYTHONIOENCODING=utf-8` |
| `Remove-Item -Recurse -Force` **silently skips** files it cannot delete | assume success | re-check every path with `Test-Path` / re-measure |
| `Clear-RecycleBin` **silently does nothing** when inherited ACLs block deletion (no error, no effect) | trust it | verify the entry count actually dropped |
| Logging captured command output without truncation | `takeown /r` + `icacls /t` over 221k files produced a **93 MB / 710k-line log** | keep the first ~20 lines plus a total count |

Also: `curl`, `wget`, `R` and `convert` are **PowerShell aliases**, not the real programs — `curl` is `Invoke-WebRequest`, and `convert` is the destructive NTFS volume converter. Call `C:\Windows\System32\curl.exe` explicitly.

## Rule 6b — Two "you can't query that" beliefs that are wrong

1. **`wsl.exe` writes UTF-16** while the console code page is 936, so reading its output gives spaced-out mojibake (`U b u n t u`). Fix the encoding before calling it, or read the registry instead:
   ```powershell
   [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
   wsl -l -v
   # or, no encoding games at all:
   Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' |
     ForEach-Object { (Get-ItemProperty $_.PSPath).DistributionName }
   ```
2. **`Get-WindowsOptionalFeature` needs elevation, `Get-CimInstance Win32_OptionalFeature` does not.** `InstallState = 1` means enabled. Do not conclude "optional features are unqueryable" from the DISM cmdlet's refusal:
   ```powershell
   Get-CimInstance Win32_OptionalFeature |
     Where-Object { $_.Name -match 'Linux|VirtualMachinePlatform' } |
     Select-Object Name,InstallState
   ```

## Rule 7 — "Access is denied" on your own files is usually ACL, not path length

Before blaming the 260-character `MAX_PATH` limit, check the owner:

```powershell
$i = Get-Item -LiteralPath $p -Force; (Get-Acl -LiteralPath $p).Owner
(Get-Acl -LiteralPath $p).Access | Select-Object IdentityReference,FileSystemRights,AccessControlType
```

Files deleted into the Recycle Bin **keep the ACL of their original location**. A deleted TeX Live tree came back owned by `BUILTIN\Administrators` with the user holding only `ReadAndExecute`, so `Clear-RecycleBin`, `Remove-Item -Force` **and** `robocopy /MIR` all failed with "Access is denied" — an easy misdiagnosis as a long-path problem. The fix was, elevated:

```powershell
takeown /f "<path>" /r /d y
icacls  "<path>" /grant "<user>:(F)" /t /c
Remove-Item -LiteralPath "<path>" -Recurse -Force
```

## Rule 8 — Anything requiring elevation

A default Windows shell is **not** elevated (the account may be in `Administrators` while the token is deny-only). `Get-WindowsOptionalFeature`, `Get-BitLockerVolume`, `Get-MpPreference`, `HKLM` writes and machine-scope installs all fail outright — do not retry them.

Hand the user a **script that self-elevates**, not a long paste block, and launch it through a `.cmd` wrapper that already carries `-ExecutionPolicy Bypass`:

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
    exit
}
```

```bat
@echo off
rem ASCII only -- cmd.exe decodes .cmd as ANSI/936
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script.ps1" %*
pause
```

**Why a wrapper beats pasting commands:** every pasted instruction is re-typed by a human in a different context. Both the `sc`-alias failure and the execution-policy failure happened exactly this way — the traps were already documented, but the *instruction* did not carry the fix. A script carries it.
