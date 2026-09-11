#requires -Version 5.1
<#
  Run-MigrationBatch.ps1 -- run Move-DataUnit.ps1 over a list of units, sequentially.
  Usage:
    powershell -NoProfile -ExecutionPolicy Bypass -File Run-MigrationBatch.ps1 -Units a,b,c -Mode Link
    powershell -NoProfile -ExecutionPolicy Bypass -File Run-MigrationBatch.ps1 -Set agents -Mode Link
#>
[CmdletBinding()]
param(
    [string[]]$Units = @(),
    [ValidateSet('agents','apps','all')]
    [string]$Set = 'agents',
    [ValidateSet('Copy','Link')]
    [string]$Mode = 'Link',
    [int]$HashSample = 0
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$One = Join-Path $ScriptDir 'Move-DataUnit.ps1'
$LogDir = 'E:\dsh\migration\logs'

$AGENTS = @('dsh-data','codex-data','codex-cache','codex-appdata','codex-docs',
            'kimi-work','kimi-webbridge','kimi-code','kimi-docs',
            'crawl4ai-data','aicompletion','modex-data','doubao-userdata','kimi-userdata')
$APPS   = @('modex-app','doubao-app','kimi-app','coze-app','ccswitch-app','nano-app')

if ($Units.Count -eq 0) {
    switch ($Set) {
        'agents' { $Units = $AGENTS }
        'apps'   { $Units = $APPS }
        'all'    { $Units = $AGENTS + $APPS }
    }
}

$batchLog = Join-Path $LogDir ('batch-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
"BATCH START $(Get-Date -Format s)  mode=$Mode  units=$($Units -join ',')" | Out-File -LiteralPath $batchLog -Encoding UTF8

foreach ($u in $Units) {
    $line = "=== $(Get-Date -Format 'HH:mm:ss') UNIT $u ==="
    Write-Host $line
    $line | Add-Content -LiteralPath $batchLog -Encoding UTF8
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $One -Unit $u -Mode $Mode -HashSample $HashSample 2>&1
    $out | Add-Content -LiteralPath $batchLog -Encoding UTF8
    $out | Select-Object -Last 6 | ForEach-Object { Write-Host "   $_" }
}

"BATCH DONE $(Get-Date -Format s)" | Add-Content -LiteralPath $batchLog -Encoding UTF8
Write-Host "batch log: $batchLog"
