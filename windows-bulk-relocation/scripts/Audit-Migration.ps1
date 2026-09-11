#requires -Version 5.1
<#
  Audit-Migration.ps1 -- 对每个已迁移单元做「源路径现在的可见内容」与「主副本/备份」的逐文件比对。
  输出：E:\dsh\migration\manifests\audit-migration.csv + 屏幕摘要
  只读，不改任何文件。
#>
[CmdletBinding()]
param()
$ErrorActionPreference='Continue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8

function Get-Map([string]$root) {
    $map = New-Object 'System.Collections.Generic.Dictionary[string,long]'
    if (-not (Test-Path -LiteralPath $root)) { return $map }
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object System.IO.DirectoryInfo $root))
    $rl = $root.TrimEnd('\').Length + 1
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $items = $null
        try { $items = $cur.GetFileSystemInfos() } catch { continue }
        foreach ($it in $items) {
            if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($it -is [System.IO.DirectoryInfo]) { $stack.Push($it) }
            else { $map[$it.FullName.Substring($rl)] = ([System.IO.FileInfo]$it).Length }
        }
    }
    return $map
}

function Compare-Pair([string]$live,[string]$ref,[string]$name) {
    if (-not (Test-Path -LiteralPath $live)) { return [pscustomobject]@{Name=$name;Live='MISSING';Ref=$ref;LiveFiles=0;RefFiles=0;Missing=0;MissingMB=0;Extra=0;SizeDiff=0;Verdict='MISSING'} }
    if (-not (Test-Path -LiteralPath $ref))  { return [pscustomobject]@{Name=$name;Live=$live;Ref='MISSING';LiveFiles=0;RefFiles=0;Missing=0;MissingMB=0;Extra=0;SizeDiff=0;Verdict='NO-REF'} }
    $a = Get-Map $live; $b = Get-Map $ref
    $missing = 0; $missingBytes = [long]0; $extra = 0; $sdiff = 0
    foreach ($k in $b.Keys) {
        if (-not $a.ContainsKey($k)) { $missing++; $missingBytes += $b[$k] }
        elseif ($a[$k] -ne $b[$k]) { $sdiff++ }
    }
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k)) { $extra++ } }
    $verdict = if ($missing -eq 0 -and $sdiff -eq 0) { 'OK' } else { 'DIFF' }
    return [pscustomobject]@{
        Name=$name; Live=$live; Ref=$ref
        LiveFiles=$a.Count; RefFiles=$b.Count
        Missing=$missing; MissingMB=[math]::Round($missingBytes/1MB,1)
        Extra=$extra; SizeDiff=$sdiff; Verdict=$verdict
    }
}

# live(现在通过链接可见) ; ref(权威副本：主副本或备份)
$PAIRS = @(
    @{ n='codex-runtimes'; live='C:\Users\76693\.cache\codex-runtimes'; ref='G:\AI\_backup\codex-runtimes.20260911-021007' },
    @{ n='codex-data';     live='C:\Users\76693\.codex';                ref='G:\AI\_backup\.codex.final-20260911-022026' },
    @{ n='codex-appdata';  live='C:\Users\76693\AppData\Local\OpenAI';  ref='G:\AI\_backup\OpenAI.20260911-021544' },
    @{ n='codex-docs';     live='C:\Users\76693\Documents\Codex';       ref='G:\AI\_backup\Codex.20260911-021305' },
    @{ n='kimi-work';      live='C:\Users\76693\.kimi-work';            ref='G:\AI\_backup\.kimi-work.20260911-021308' },
    @{ n='kimi-webbridge'; live='C:\Users\76693\.kimi-webbridge';       ref='G:\AI\_backup\.kimi-webbridge.20260911-021312' },
    @{ n='kimi-code';      live='C:\Users\76693\.kimi-code';            ref='G:\AI\_backup\.kimi-code.20260911-021028' },
    @{ n='kimi-docs';      live='C:\Users\76693\Documents\kimi';        ref='G:\AI\_backup\kimi.20260911-021030' },
    @{ n='kimi-userdata';  live='C:\Users\76693\AppData\Roaming\kimi-desktop'; ref='G:\AI\_backup\kimi-desktop.20260911-021321' },
    @{ n='kimi-app';       live='C:\Users\76693\AppData\Local\Programs\kimi-desktop'; ref='G:\AI\_backup\kimi-desktop.20260911-021433' },
    @{ n='ccswitch-data';  live='C:\Users\76693\.cc-switch';            ref='G:\AI\_backup\.cc-switch.20260911-020934' },
    @{ n='ccswitch-app';   live='E:\CC Switch';                         ref='G:\AI\_backup\CC Switch.20260911-021438' },
    @{ n='coze-app';       live='E:\Coze';                              ref='G:\AI\_backup\Coze.20260911-021436' },
    @{ n='nano-app';       live='E:\Nano';                              ref='G:\AI\_backup\Nano.20260911-021441' },
    @{ n='doubao-app';     live='G:\Doubao';                            ref='G:\AI\_backup\Doubao.20260911-021428' },
    @{ n='doubao-userdata';live='C:\Users\76693\AppData\Local\Doubao';  ref='G:\AI\_backup\Doubao.20260911-021315' },
    @{ n='crawl4ai';       live='C:\Users\76693\.crawl4ai';             ref='G:\AI\_backup\.crawl4ai.20260911-021031' },
    @{ n='ai_completion';  live='C:\Users\76693\.ai_completion';        ref='G:\AI\_backup\.ai_completion.20260911-021034' },
    @{ n='dsh-data';       live='C:\Users\76693\.dsh';                  ref='G:\AI\_backup\dsh-not-migrated' },
    @{ n='modex-data';     live='G:\modex';                             ref='G:\Code\02-竞赛\Modex-Agent-Workspace' }
)

$results = New-Object System.Collections.Generic.List[object]
foreach ($p in $PAIRS) {
    Write-Host "auditing $($p.n) ..."
    $results.Add((Compare-Pair $p.live $p.ref $p.n))
}
$results | Export-Csv -LiteralPath 'E:\dsh\migration\manifests\audit-migration.csv' -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host ("{0,-18} {1,-8} {2,10} {3,10} {4,8} {5,10} {6,8} {7,8}" -f 'UNIT','VERDICT','LIVE','REF','MISSING','MISS_MB','EXTRA','SIZEDIFF')
Write-Host ('-'*92)
foreach ($r in $results) {
    Write-Host ("{0,-18} {1,-8} {2,10:N0} {3,10:N0} {4,8:N0} {5,10:N1} {6,8:N0} {7,8:N0}" -f `
        $r.Name, $r.Verdict, $r.LiveFiles, $r.RefFiles, $r.Missing, $r.MissingMB, $r.Extra, $r.SizeDiff)
}
$bad = @($results | Where-Object { $_.Verdict -ne 'OK' })
Write-Host ""
if ($bad.Count -eq 0) { Write-Host "全部单元校验通过。" } else { Write-Host ("需要处理: " + (($bad | ForEach-Object { $_.Name }) -join ', ')) }
