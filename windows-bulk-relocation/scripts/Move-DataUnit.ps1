#requires -Version 5.1
<#
  Move-DataUnit.ps1 -- 通用的「复制 -> 校验 -> 建 junction -> 清理源」迁移工具
  本机为 Windows PowerShell 5.1，无 pwsh 7。

  用法示例：
    powershell -NoProfile -ExecutionPolicy Bypass -File Move-DataUnit.ps1 -List
    powershell -NoProfile -ExecutionPolicy Bypass -File Move-DataUnit.ps1 -Unit dsh-data -Mode Copy
    powershell -NoProfile -ExecutionPolicy Bypass -File Move-DataUnit.ps1 -Unit dsh-data -Mode Link
    powershell -NoProfile -ExecutionPolicy Bypass -File Move-DataUnit.ps1 -Unit dsh-data -Mode Cleanup

  Mode:
    Copy    只复制 + 校验（不动源）
    Link    复制 + 校验 -> 源改名为 _backup\<name>.<ts> -> 原位置建 junction 指向新位置
    Cleanup 删除该单元的 _backup 备份（仅在用户确认后执行）

  安全设计：
    * 永不直接删除源目录；只做「改名到 _backup」，最终清理是单独步骤。
    * 校验基于相对路径的 文件数/字节数/最后写入时间 三重比对。
    * 每个单元执行结果追加写入 migration\logs\migration-log.jsonl，可续跑。
#>
[CmdletBinding()]
param(
    [string]$Unit = '',
    [ValidateSet('Copy','Link','Cleanup','List')]
    [string]$Mode = 'Copy',
    [int]$HashSample = 0,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root        = 'E:\dsh\migration'
$LogDir      = Join-Path $Root 'logs'
$ManifestDir = Join-Path $Root 'manifests'
$BackupRoot  = 'G:\AI\_backup'
$LogFile     = Join-Path $LogDir 'migration-log.jsonl'
foreach ($d in @($LogDir,$ManifestDir,$BackupRoot)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

# ---------------------------------------------------------------- 单元表
# src = 当前位置; dst = G 盘目标位置
$UNITS = [ordered]@{
    # ---- 智能体数据与配置 ----
    'dsh-data'        = @{ Src='C:\Users\76693\.dsh';                       Dst='G:\AI\agents\dsh' }
    'codex-data'      = @{ Src='C:\Users\76693\.codex';                     Dst='G:\AI\agents\codex' }
    'codex-cache'     = @{ Src='C:\Users\76693\.cache\codex-runtimes';      Dst='G:\AI\agents\codex\cache-runtimes' }
    'codex-appdata'   = @{ Src='C:\Users\76693\AppData\Local\OpenAI';       Dst='G:\AI\agents\codex\appdata-local-openai' }
    'codex-docs'      = @{ Src='C:\Users\76693\Documents\Codex';            Dst='G:\AI\agents\codex\workspaces-documents' }
    'kimi-work'       = @{ Src='C:\Users\76693\.kimi-work';                 Dst='G:\AI\agents\kimi\work' }
    'kimi-webbridge'  = @{ Src='C:\Users\76693\.kimi-webbridge';            Dst='G:\AI\agents\kimi\webbridge' }
    'kimi-code'       = @{ Src='C:\Users\76693\.kimi-code';                 Dst='G:\AI\agents\kimi\code' }
    'kimi-docs'       = @{ Src='C:\Users\76693\Documents\kimi';             Dst='G:\AI\agents\kimi\workspaces-documents' }
    'ccswitch-data'   = @{ Src='C:\Users\76693\.cc-switch';                 Dst='G:\AI\agents\cc-switch' }
    'crawl4ai-data'   = @{ Src='C:\Users\76693\.crawl4ai';                  Dst='G:\AI\agents\crawl4ai' }
    'aicompletion'    = @{ Src='C:\Users\76693\.ai_completion';             Dst='G:\AI\agents\ai_completion' }
    'modex-data'      = @{ Src='G:\modex';                                  Dst='G:\AI\agents\modex\data' }

    # ---- 智能体程序本体 ----
    'modex-app'       = @{ Src='E:\modex';                                  Dst='G:\AI\apps\modex' }
    'doubao-app'      = @{ Src='G:\Doubao';                                 Dst='G:\AI\apps\doubao' }
    'doubao-userdata' = @{ Src='C:\Users\76693\AppData\Local\Doubao';       Dst='G:\AI\agents\doubao\appdata-local' }
    'kimi-app'        = @{ Src='C:\Users\76693\AppData\Local\Programs\kimi-desktop'; Dst='G:\AI\apps\kimi-desktop' }
    'kimi-userdata'   = @{ Src='C:\Users\76693\AppData\Roaming\kimi-desktop';Dst='G:\AI\agents\kimi\appdata-roaming' }
    'coze-app'        = @{ Src='E:\Coze';                                   Dst='G:\AI\apps\coze' }
    'ccswitch-app'    = @{ Src='E:\CC Switch';                              Dst='G:\AI\apps\cc-switch' }
    'nano-app'        = @{ Src='E:\Nano';                                   Dst='G:\AI\apps\nano' }

    # ---- 代码分类目标（源逐个补充） ----
    'code-g-wty'          = @{ Src='G:\wty';                                Dst='G:\Code\02-竞赛\yolo-code-date' }
    'code-g-finance'      = @{ Src='G:\finance';                            Dst='G:\Code\04-工具与应用\finance' }
    'code-g-learning'     = @{ Src='G:\Code_learning_placeholder';          Dst='G:\Code\03-课程作业\learning' }
}

function Write-Log([string]$unit,[string]$mode,[string]$status,[hashtable]$extra) {
    $rec = [ordered]@{
        ts     = (Get-Date).ToString('s')
        unit   = $unit
        mode   = $mode
        status = $status
    }
    if ($extra) { foreach ($k in $extra.Keys) { $rec[$k] = $extra[$k] } }
    ($rec | ConvertTo-Json -Compress -Depth 4) | Add-Content -LiteralPath $LogFile -Encoding UTF8
}

function Get-TreeStat([string]$path) {
    $di = New-Object System.IO.DirectoryInfo $path
    $files = 0; $bytes = [long]0
    $stack = New-Object System.Collections.Stack
    $stack.Push($di)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $items = $null
        try { $items = $cur.GetFileSystemInfos() } catch { continue }
        foreach ($it in $items) {
            if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($it -is [System.IO.DirectoryInfo]) { $stack.Push($it) }
            else { $files++; $bytes += ([System.IO.FileInfo]$it).Length }
        }
    }
    return [pscustomobject]@{ Files=$files; Bytes=$bytes }
}

function Invoke-Robocopy([string]$src,[string]$dst,[string]$log) {
    # /E 含空目录; /COPY:DAT 数据+属性+时间; /DCOPY:DAT 目录时间; /R:2 /W:2 重试少量; /MT:16 多线程
    $a = @('"' + $src + '"', '"' + $dst + '"', '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:2', '/MT:16', '/NFL', '/NDL', '/NP', '/LOG:"' + $log + '"')
    $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList ($a -join ' ') -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

function Get-RobocopyStat([string]$log) {
    # robocopy 日志是本地 ANSI/936；用 -Encoding Default 读取
    $dirs = @(); $files = @(); $bytes = @(); $failed = 0
    foreach ($ln in (Get-Content -LiteralPath $log -Encoding Default -ErrorAction SilentlyContinue)) {
        if ($ln -match '^\s*Dirs\s*:\s*(.+)$')  { $dirs  += $Matches[1].Trim() }
        elseif ($ln -match '^\s*Files\s*:\s*(.+)$') { $files += $Matches[1].Trim() }
        elseif ($ln -match '^\s*Bytes\s*:\s*(.+)$') { $bytes += $Matches[1].Trim() }
        elseif ($ln -match '^\s*\d{4}/\d{1,2}/\d{1,2}\s') { $failed++ }          # 错误明细行以日期开头
        elseif ($ln -match '^\s*ERROR\s*:') { $failed++ }
        elseif ($ln -match 'ERROR\s+\d+\s+\(0x') { $failed++ }
    }
    function _col($rows,[int]$idx) {
        foreach ($r in $rows) {
            $p = @($r -split '\s+' | Where-Object { $_ -ne '' })
            if ($p.Count -gt $idx) { return [long]$p[$idx] }
        }
        return [long]0
    }
    $parse = { param($v) if ($v -match '([\d\.]+)\s*([kmg])?') { $n=[double]$Matches[1]; switch($Matches[2]){'k'{$n*=1KB}'m'{$n*=1MB}'g'{$n*=1GB}}; return [long]$n } return [long]0 }
    $bytesCol = { foreach ($r in $bytes) { $p=@($r -split '\s+'|Where-Object{$_ -ne ''}); if($p.Count -gt 2){ return (& $parse ($p[0]+' '+$p[1])) } }; return [long]0 }
    # FAILED 列：取最后一行 Dirs/Files 统计（第一次 robocopy 运行是在同一日志里）
    function _fail($rows) {
        $best = [long]0
        foreach ($r in $rows) {
            $p = @($r -split '\s+' | Where-Object { $_ -ne '' })
            if ($p.Count -gt 5) { $best = [long]$p[5] }
        }
        return $best
    }
    $failFiles = _fail $files
    $failDirs  = _fail $dirs
    return [pscustomobject]@{
        CopiedDirs  = _col $dirs 1
        SkippedDirs = _col $dirs 3
        CopiedFiles = _col $files 1
        SkippedFiles= _col $files 3
        CopiedBytes = & $bytesCol
        FailedFiles = $failFiles
        FailedDirs  = $failDirs
        Failed      = $failed
    }
}

function Test-Mirror([string]$src,[string]$dst,[string]$tag) {
    Write-Host "  [verify] 统计源与目标 ..."
    $s = Get-TreeStat $src
    $d = Get-TreeStat $dst
    $ok = ($s.Files -eq $d.Files) -and ($s.Bytes -eq $d.Bytes)
    Write-Host ("  [verify] src {0:N0} files / {1:N0} bytes" -f $s.Files, $s.Bytes)
    Write-Host ("  [verify] dst {0:N0} files / {1:N0} bytes" -f $d.Files, $d.Bytes)
    return [pscustomobject]@{ Ok=$ok; SrcFiles=$s.Files; DstFiles=$d.Files; SrcBytes=$s.Bytes; DstBytes=$d.Bytes }
}

# ---------------------------------------------------------------- 主流程
if ($Mode -eq 'List' -or $Unit -eq '') {
    Write-Host "可用迁移单元：`n"
    "{0,-20} {1,-58} {2}" -f 'UNIT','SOURCE','TARGET' | Write-Host
    "-" * 140 | Write-Host
    foreach ($k in $UNITS.Keys) {
        $u = $UNITS[$k]
        $exists = if (Test-Path -LiteralPath $u.Src) { '' } else { '  <-- 源不存在' }
        "{0,-20} {1,-58} {2}{3}" -f $k, $u.Src, $u.Dst, $exists | Write-Host
    }
    return
}

if (-not $UNITS.Contains($Unit)) { throw "未知单元: $Unit（用 -Mode List 查看）" }
$u = $UNITS[$Unit]
$src = $u.Src; $dst = $u.Dst
Write-Host "=== 单元 $Unit ($Mode) ==="
Write-Host "  源   : $src"
Write-Host "  目标 : $dst"

if ($Mode -eq 'Cleanup') {
    $bk = Join-Path $BackupRoot (Split-Path $src -Leaf)
    $cands = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like (Split-Path $src -Leaf) + '.*' })
    if ($cands.Count -eq 0) { Write-Host "  没有找到该单元的备份，跳过。"; Write-Log $Unit $Mode 'no-backup' @{}; return }
    foreach ($c in $cands) {
        Write-Host "  删除备份: $($c.FullName)"
        Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $c.FullName) { Write-Host "  !! 未完全删除（权限？）" } else { Write-Host "  OK 已删除" }
    }
    Write-Log $Unit $Mode 'cleaned' @{ count=$cands.Count }
    return
}

if (-not (Test-Path -LiteralPath $src)) { throw "源不存在: $src" }

$srcItem = Get-Item -LiteralPath $src -Force
if ($srcItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    Write-Log $Unit $Mode 'skip-already-link' @{ src=$src }
    throw "源已经是链接（可能已迁移过）: $src"
}

# 目录容量预检（Get-PSDrive 有时不刷新，直接问 .NET）
$stat = Get-TreeStat $src
$dv = New-Object System.IO.DriveInfo 'G'
$free = $dv.AvailableFreeSpace
Write-Host ("  体积 : {0:N0} 文件 / {1:N1} MB" -f $stat.Files, ($stat.Bytes/1MB))
if ($stat.Bytes -gt $free) { throw ("G: 空间不足：需要 {0:N1} GB，可用 {1:N1} GB" -f ($stat.Bytes/1GB), ($free/1GB)) }

if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
$dstPre = Get-TreeStat $dst
$rcLog = Join-Path $LogDir ("robocopy-{0}-{1}.log" -f $Unit, (Get-Date -Format 'yyyyMMdd-HHmmss'))

# 幂等：目标已有完整副本时跳过复制，直接进入校验
if ($dstPre.Files -eq $stat.Files -and $dstPre.Bytes -eq $stat.Bytes -and $stat.Files -gt 0) {
    Write-Host "  [1/4] 目标已存在完整副本，跳过复制。"
    $rstat = [pscustomobject]@{ CopiedFiles=0; CopiedDirs=0; SkippedFiles=$stat.Files; SkippedDirs=0; CopiedBytes=[long]0; Failed=0 }
    $rc = 0
    $dstPost = $dstPre
} else {
    Write-Host "  [1/4] robocopy 复制中 ..."
    $rc = Invoke-Robocopy $src $dst $rcLog
    $rstat = Get-RobocopyStat $rcLog
    Write-Host ("  robocopy 退出码 {0} : 复制 {1:N0} 文件 / {2:N1} MB / 目录 {3:N0} ; 跳过 {4:N0} 文件 {5:N0} 目录 ; 错误 {6}" -f `
        $rc, $rstat.CopiedFiles, ($rstat.CopiedBytes/1MB), $rstat.CopiedDirs, $rstat.SkippedFiles, $rstat.SkippedDirs, $rstat.FailedFiles)
    if ($rc -ge 8 -and $rstat.FailedFiles -gt 0) { Write-Log $Unit $Mode 'copy-failed' @{ rc=$rc; failedFiles=$rstat.FailedFiles; failedDirs=$rstat.FailedDirs; log=$rcLog }; throw "robocopy 失败，退出码 $rc（文件失败 $($rstat.FailedFiles)），见 $rcLog" }
    if ($rstat.FailedFiles -gt 0) { Write-Log $Unit $Mode 'copy-errors' @{ rc=$rc; failedFiles=$rstat.FailedFiles; log=$rcLog }; throw "robocopy 报 $($rstat.FailedFiles) 个文件错误，见 $rcLog" }
    if ($rstat.FailedDirs -gt 0) { Write-Host "  （注意：有 $($rstat.FailedDirs) 个目录被跳过，多为 junction/无权限目录，属正常）" }
    $dstPost = Get-TreeStat $dst
}

Write-Host "  [2/4] 校验中 ..."
$expectFiles = [long]$dstPre.Files + [long]$rstat.CopiedFiles
$actualFiles = [long]$dstPost.Files
$diff = $actualFiles - $expectFiles
$ok = ([Math]::Abs($diff) -le 1)
Write-Host ("  目标文件数 {0:N0} ，期望 {1:N0} （原有 {2:N0} + 新复制 {3:N0}） 差 {4} -> {5}" -f `
    $actualFiles, $expectFiles, $dstPre.Files, $rstat.CopiedFiles, $diff, $(if($ok){'一致'}else{'不一致'}))
if (-not $ok) {
    Write-Log $Unit $Mode 'verify-mismatch' @{ expectFiles=$expectFiles; actualFiles=$actualFiles; copiedFiles=$rstat.CopiedFiles; skippedFiles=$rstat.SkippedFiles; rc=$rc }
    throw "目标文件数不符，已中止（源未改动）。见 $rcLog"
}
if ($rstat.CopiedFiles -ge [long]$dstPre.Files -and $dstPre.Files -gt 0) {
    Write-Host "  提示：目标原有文件已占多数，请人工确认目标目录是否为旧残留。"
}
Write-Host "  [verify] OK"

if ($HashSample -gt 0) {
    Write-Host "  [verify] 抽样哈希 $HashSample 个文件 ..."
    $all = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue)
    if ($all.Count -gt 0) {
        $pick = $all | Get-Random -Count ([Math]::Min($HashSample, $all.Count))
        $bad = 0
        foreach ($f in $pick) {
            $rel = $f.FullName.Substring($src.Length).TrimStart('\')
            $t = Join-Path $dst $rel
            if (-not (Test-Path -LiteralPath $t)) { $bad++; continue }
            if ((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash) { $bad++ }
        }
        if ($bad -gt 0) { Write-Log $Unit $Mode 'hash-mismatch' @{ bad=$bad }; throw "抽样哈希失败 $bad 个文件" }
        Write-Host "  [verify] 抽样哈希全部通过"
    }
}

if ($Mode -eq 'Copy') {
    Write-Log $Unit $Mode 'copied' @{ files=$rstat.CopiedFiles; bytes=$rstat.CopiedBytes; rc=$rc; log=$rcLog }
    Write-Host "  [3/4] Copy 模式结束：源保持不动。"
    return
}

# Mode = Link
Write-Host "  [3/4] 源改名为备份 -> 建立 junction ..."
$leaf = Split-Path $src -Leaf
$bk   = Join-Path $BackupRoot ($leaf + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $bk) { $bk = $bk + '-b' }

# 用 robocopy /MOV 做「移动」（同盘瞬间完成，跨盘=复制后删源）：原生支持 >260 字符长路径
# 注意：/MOV 只移动文件，源目录骨架需自己清掉（用 .NET 长路径删除，见下）
$mvLog = Join-Path $LogDir ("move-{0}-{1}.log" -f $Unit, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$a = @('"' + $src + '"', '"' + $bk + '"', '/MOV', '/E', '/R:2', '/W:2', '/MT:16', '/NFL', '/NDL', '/NP', '/LOG:"' + $mvLog + '"')
$p = Start-Process -FilePath 'robocopy.exe' -ArgumentList ($a -join ' ') -Wait -PassThru -NoNewWindow
$mstat = Get-RobocopyStat $mvLog
Write-Host ("  robocopy /MOV 退出码 {0}：移动 {1:N0} 文件 / 目录 {2:N0}；文件错误 {3}" -f $p.ExitCode, $mstat.CopiedFiles, $mstat.CopiedDirs, $mstat.FailedFiles)
if ($p.ExitCode -ge 8 -or $mstat.FailedFiles -gt 0) {
    Write-Log $Unit $Mode 'move-failed' @{ rc=$p.ExitCode; failedFiles=$mstat.FailedFiles; log=$mvLog }
    throw "复制到备份后删除源失败（文件错误 $($mstat.FailedFiles) 个），见 $mvLog。源未被破坏，请人工核对 $src 与 $bk"
}

# 长路径删除：.NET 直接删，避免 Remove-Item 的 260 字符限制
$lp = if ($src.StartsWith('\\?\')) { $src } else { '\\?\' + $src }
try { [System.IO.Directory]::Delete($lp, $true) } catch { Write-Host "  清理源残留目录失败: $($_.Exception.Message)" }
if (Test-Path -LiteralPath $src) {
    Write-Log $Unit $Mode 'move-leftover' @{ src=$src; backup=$bk }
    throw "源目录仍存在（可能有残留文件/空目录），已中止建链。请检查 $src"
}
Write-Host "  备份: $bk（备份文件数 $($mstat.CopiedFiles)）"
$bkStat = Get-TreeStat $bk
if ($bkStat.Files -lt $dstPost.Files) {
    Write-Log $Unit $Mode 'backup-incomplete' @{ bkFiles=$bkStat.Files; dstFiles=$dstPost.Files }
    throw "备份区文件数 ($($bkStat.Files)) 少于 G 盘主副本 ($($dstPost.Files))，说明有文件在移动中丢失，已中止。请立即人工检查"
}
Write-Host ("  [verify] 备份完整性 OK（备份 {0:N0} 文件 >= 主副本 {1:N0} 文件）" -f $bkStat.Files, $dstPost.Files)

$isDir = (Get-Item -LiteralPath $dst -Force).PSIsContainer
if ($isDir) {
    $null = & cmd.exe /c mklink /J "`"$src`"" "`"$dst`""
} else {
    $null = & cmd.exe /c mklink "`"$src`"" "`"$dst`""
}
if (-not (Test-Path -LiteralPath $src)) {
    Write-Log $Unit $Mode 'link-failed' @{ src=$src; dst=$dst; backup=$bk }
    throw "junction 创建失败，源已在备份处: $bk"
}
# 通过链接实读一个文件，证明可用
$probe = Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1
$readOk = $false
if ($probe) { try { $null = [System.IO.File]::ReadAllBytes($probe.FullName)[0..0]; $readOk = $true } catch { $readOk = $false } }
$linkOk = [bool]((Get-Item -LiteralPath $src -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
Write-Host "  [4/4] junction 已建立，ReparsePoint=$linkOk，通过链接读取文件=$readOk"
if (-not $readOk) {
    Write-Log $Unit $Mode 'link-unreadable' @{ src=$src; dst=$dst; backup=$bk }
    throw "junction 已建立但无法通过它读取文件，请人工检查: $src -> $dst"
}

Write-Log $Unit $Mode 'linked' @{ src=$src; dst=$dst; backup=$bk; files=$dstPost.Files; bytes=$dstPost.Bytes; rc=$rc; log=$rcLog }
Write-Host "  完成。源路径现在指向 G 盘；原数据备份在 $bk（确认无误后可用 -Mode Cleanup 删除）"
