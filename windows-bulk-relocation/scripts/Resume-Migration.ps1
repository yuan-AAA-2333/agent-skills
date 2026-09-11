#requires -Version 5.1
<#
  Resume-Migration.ps1 -- run Move-DataUnit.ps1 only for units whose source is NOT yet a junction.
  Copy-only units (dsh-data etc.) are listed separately and use -Mode Copy.
#>
[CmdletBinding()]
param(
    [string[]]$Only = @(),
    [string[]]$CopyOnly = @('dsh-data'),
    [ValidateSet('Link','Copy')]
    [string]$Mode = 'Link'
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$One = Join-Path $Dir 'Move-DataUnit.ps1'
$BatchLog = Join-Path 'E:\dsh\migration\logs' ('resume-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

# unit -> source path (must match Move-DataUnit.ps1)
$MAP = [ordered]@{
    'dsh-data'='C:\Users\76693\.dsh'; 'codex-data'='C:\Users\76693\.codex';
    'codex-cache'='C:\Users\76693\.cache\codex-runtimes'; 'codex-appdata'='C:\Users\76693\AppData\Local\OpenAI';
    'codex-docs'='C:\Users\76693\Documents\Codex'; 'kimi-work'='C:\Users\76693\.kimi-work';
    'kimi-webbridge'='C:\Users\76693\.kimi-webbridge'; 'kimi-code'='C:\Users\76693\.kimi-code';
    'kimi-docs'='C:\Users\76693\Documents\kimi'; 'ccswitch-data'='C:\Users\76693\.cc-switch';
    'crawl4ai-data'='C:\Users\76693\.crawl4ai'; 'aicompletion'='C:\Users\76693\.ai_completion';
    'modex-data'='G:\modex'; 'doubao-userdata'='C:\Users\76693\AppData\Local\Doubao';
    'kimi-userdata'='C:\Users\76693\AppData\Roaming\kimi-desktop';
    'modex-app'='E:\modex'; 'doubao-app'='G:\Doubao'; 'kimi-app'='C:\Users\76693\AppData\Local\Programs\kimi-desktop';
    'coze-app'='E:\Coze'; 'ccswitch-app'='E:\CC Switch'; 'nano-app'='E:\Nano'
}

$todo = New-Object System.Collections.Generic.List[object]
foreach ($k in $MAP.Keys) {
    if ($Only.Count -gt 0 -and ($Only -notcontains $k)) { continue }
    $src = $MAP[$k]
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $isLink = [bool]((Get-Item -LiteralPath $src -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    if ($CopyOnly -contains $k) { $unitMode = 'Copy' } else { $unitMode = $Mode }
    if ($isLink -and $unitMode -eq 'Link') { Write-Host "SKIP  $k  (已是链接)"; continue }
    $todo.Add([pscustomobject]@{ Unit=$k; Src=$src; Mode=$unitMode })
}

if ($todo.Count -eq 0) { Write-Host "没有待处理单元。"; return }
Write-Host ("待处理 {0} 个单元: {1}" -f $todo.Count, (($todo | ForEach-Object { $_.Unit }) -join ', '))
"RESUME $(Get-Date -Format s): $((($todo | ForEach-Object { $_.Unit + ':' + $_.Mode }) -join ', '))" | Out-File -LiteralPath $BatchLog -Encoding UTF8

foreach ($t in $todo) {
    Write-Host "`n>>> $($t.Unit) [$($t.Mode)]"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $One -Unit $t.Unit -Mode $t.Mode -HashSample 2 2>&1
    $out | Add-Content -LiteralPath $BatchLog -Encoding UTF8
    $out | Select-Object -Last 5 | ForEach-Object { Write-Host "   $_" }
}
"DONE $(Get-Date -Format s)" | Add-Content -LiteralPath $BatchLog -Encoding UTF8
Write-Host "`nlog: $BatchLog"
