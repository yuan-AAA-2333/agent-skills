#requires -Version 5.1
<#
  Compare-Tree.ps1 -- 两个目录树逐文件比对（相对路径 + 大小），输出差异明细
  用法: ... -Compare-Tree.ps1 -A <源> -B <目标> [-Exclude a,b] [-Out file.csv]
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B,
      [string[]]$Exclude = @(),[string]$Out = '',[int]$MaxShow = 25)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-Map([string]$root,[string[]]$excl) {
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
            $rel = $it.FullName.Substring($rl)
            $skip = $false
            foreach ($e in $excl) { if ($rel -like ($e + '*')) { $skip = $true; break } }
            if ($skip) { continue }
            if ($it -is [System.IO.DirectoryInfo]) { $stack.Push($it) }
            else { $map[$rel] = ([System.IO.FileInfo]$it).Length }
        }
    }
    return $map
}

Write-Host "扫描 A: $A"
$ma = Get-Map $A $Exclude
Write-Host "扫描 B: $B"
$mb = Get-Map $B $Exclude
Write-Host ("A: {0:N0} 文件 / {1:N1} MB" -f $ma.Count, (($ma.Values | Measure-Object -Sum).Sum/1MB))
Write-Host ("B: {0:N0} 文件 / {1:N1} MB" -f $mb.Count, (($mb.Values | Measure-Object -Sum).Sum/1MB))

$onlyA = New-Object System.Collections.Generic.List[object]
$onlyB = New-Object System.Collections.Generic.List[object]
$sizeDiff = New-Object System.Collections.Generic.List[object]
foreach ($k in $ma.Keys) {
    if (-not $mb.ContainsKey($k)) { $onlyA.Add([pscustomobject]@{ Rel=$k; BytesA=$ma[$k]; BytesB=0 }) }
    elseif ($mb[$k] -ne $ma[$k]) { $sizeDiff.Add([pscustomobject]@{ Rel=$k; BytesA=$ma[$k]; BytesB=$mb[$k] }) }
}
foreach ($k in $mb.Keys) { if (-not $ma.ContainsKey($k)) { $onlyB.Add([pscustomobject]@{ Rel=$k; BytesA=0; BytesB=$mb[$k] }) } }

Write-Host ""
Write-Host ("只在 A 存在 : {0:N0}  个（合计 {1:N1} MB）" -f $onlyA.Count, (($onlyA | Measure-Object BytesA -Sum).Sum/1MB))
Write-Host ("只在 B 存在 : {0:N0}  个（合计 {1:N1} MB）" -f $onlyB.Count, (($onlyB | Measure-Object BytesB -Sum).Sum/1MB))
Write-Host ("大小不一致  : {0:N0}  个" -f $sizeDiff.Count)

if ($onlyA.Count -gt 0) { Write-Host "`n-- 只在 A 的样本 --"; $onlyA | Select-Object -First $MaxShow | ForEach-Object { "  {0,12:N0}  {1}" -f $_.BytesA, $_.Rel } }
if ($onlyB.Count -gt 0) { Write-Host "`n-- 只在 B 的样本 --"; $onlyB | Select-Object -First $MaxShow | ForEach-Object { "  {0,12:N0}  {1}" -f $_.BytesB, $_.Rel } }
if ($sizeDiff.Count -gt 0) { Write-Host "`n-- 大小不一致样本 --"; $sizeDiff | Select-Object -First $MaxShow | ForEach-Object { "  A={0,12:N0} B={1,12:N0}  {2}" -f $_.BytesA, $_.BytesB, $_.Rel } }

if ($Out) {
    $all = @()
    foreach ($x in $onlyA) { $all += [pscustomobject]@{ Type='OnlyA'; Rel=$x.Rel; BytesA=$x.BytesA; BytesB=$x.BytesB } }
    foreach ($x in $onlyB) { $all += [pscustomobject]@{ Type='OnlyB'; Rel=$x.Rel; BytesA=$x.BytesA; BytesB=$x.BytesB } }
    foreach ($x in $sizeDiff) { $all += [pscustomobject]@{ Type='SizeDiff'; Rel=$x.Rel; BytesA=$x.BytesA; BytesB=$x.BytesB } }
    if ($all.Count -gt 0) { $all | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8; Write-Host "`n明细已写入: $Out" }
    else { Write-Host "`n两棵树完全一致。" }
}
