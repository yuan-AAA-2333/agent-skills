#requires -Version 5.1
<#
  Measure-Tree.ps1 -- 列出目录下各子目录的体积/文件数（只读，快）
  用法: ... -Measure-Tree.ps1 -Root "G:\wty" [-Depth 2] [-SortMB] [-Top 30] [-ExtSummary]
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root,[int]$Depth=2,[int]$Top=40,[switch]$ExtSummary)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-Stat([string]$p) {
    $di = New-Object System.IO.DirectoryInfo $p
    $files=0; $bytes=[long]0; $newest=[datetime]'1900-01-01'
    $ext = @{}
    $stack = New-Object System.Collections.Stack
    $stack.Push($di)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $items=$null
        try { $items = $cur.GetFileSystemInfos() } catch { continue }
        foreach ($it in $items) {
            if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($it -is [System.IO.DirectoryInfo]) { $stack.Push($it) }
            else {
                $fi=[System.IO.FileInfo]$it
                $files++; $bytes += $fi.Length
                if ($fi.LastWriteTime -gt $newest) { $newest = $fi.LastWriteTime }
                if ($ExtSummary) {
                    $e = $fi.Extension.ToLower(); if (-not $e) { $e='(none)' }
                    if ($ext.ContainsKey($e)) { $ext[$e] += $fi.Length } else { $ext[$e] = $fi.Length }
                }
            }
        }
    }
    return [pscustomobject]@{ Files=$files; MB=[math]::Round($bytes/1MB,1); Newest=$newest; Ext=$ext }
}

$base = ($Root.TrimEnd('\').Split('\')).Count
$rows = New-Object System.Collections.Generic.List[object]
$stack = New-Object System.Collections.Stack
$stack.Push($Root)
while ($stack.Count -gt 0) {
    $cur = $stack.Pop()
    $d = ($cur.TrimEnd('\').Split('\')).Count - $base
    $st = Get-Stat $cur
    $rows.Add([pscustomobject]@{ Path=$cur; Depth=$d; Files=$st.Files; MB=$st.MB; Newest=$st.Newest.ToString('yyyy-MM-dd') })
    if ($d -lt $Depth - 1) {
        foreach ($sub in (Get-ChildItem -LiteralPath $cur -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            $stack.Push($sub.FullName)
        }
    }
}
$rows | Where-Object { $_.Path -ne $Root } | Sort-Object MB -Descending | Select-Object -First $Top |
    Format-Table -AutoSize Path,Depth,Files,MB,Newest | Out-String -Width 200 | Write-Host
$tot = $rows | Where-Object { $_.Path -eq $Root }
Write-Host ("合计 {0}: {1:N0} 文件 / {2:N1} MB（{3:N2} GB）" -f $Root, $tot.Files, $tot.MB, ($tot.MB/1024))

if ($ExtSummary) {
    $all = Get-Stat $Root
    Write-Host "`n-- 扩展名占用 Top 20 --"
    $all.Ext.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20 |
        ForEach-Object { "{0,12:N1} MB  {1}" -f ($_.Value/1MB), $_.Key }
}
