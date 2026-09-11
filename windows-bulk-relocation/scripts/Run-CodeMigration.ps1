#requires -Version 5.1
<#
  Run-CodeMigration.ps1 -- 按清单依次迁移代码单元
  用法: ... Run-CodeMigration.ps1 -Units a,b,c   （不带 -Units 则跑默认全部剩余）
#>
[CmdletBinding()]
param([string[]]$Units = @())
$ErrorActionPreference='Continue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$Dir=Split-Path -Parent $MyInvocation.MyCommand.Path
$One=Join-Path $Dir 'Move-CodeUnit.ps1'
$Log="$Dir\..\logs\code-batch-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
if($Units.Count -eq 0){
    $Units = @('modex','math-modeling-research','aerospace-master','model-teaching',
               'archive-model-dir','archive-model-zip','archive-mhagent','archive-zips-kimi',
               'archive-zips-kimi2','archive-phenglei-zip','credit-scoring','pingdou-app')
}
foreach($u in $Units){
    Write-Host "`n##### $u #####"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $One -Unit $u -Mode Link 2>&1
    $out | Add-Content -LiteralPath $Log -Encoding UTF8
    $out | Where-Object { $_ -notmatch '^\s*$' } | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" }
}
Write-Host "`nlog: $Log"
