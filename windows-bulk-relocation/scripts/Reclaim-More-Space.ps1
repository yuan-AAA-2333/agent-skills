#requires -Version 5.1
<#
  Reclaim-More-Space.ps1 -- 低风险空间回收：把体积大的「纯缓存/纯数据」目录迁到 G: 并用 junction 回指。
  每个单元都：测量 -> 复制 -> 校验 -> 源改名到备份 -> 建 junction -> 通过链接复读验证。
  用法: powershell -NoProfile -ExecutionPolicy Bypass -File Reclaim-More-Space.ps1 [-Plan] [-Only name]
#>
[CmdletBinding()]
param([switch]$Plan, [string]$Only = '')
$ErrorActionPreference='Continue'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8

$BackupRoot = 'G:\AI\_backup'
$LogDir     = 'E:\dsh\migration\logs'

$UNITS = [ordered]@{
    'vscode-ext'   = @{ Src='C:\Users\76693\.vscode\extensions';      Dst='G:\AI\data\vscode-extensions';
                        Note='VS Code 扩展目录（13k 文件 / 245MB）。VS Code 通过链接读取扩展，行为不变。' }
    'npm-cache'    = @{ Src='C:\Users\76693\AppData\Local\npm-cache'; Dst='G:\AI\data\npm-cache';
                        Note='npm 缓存（29.6k 文件 / 649MB）。可用 npm config set cache 直接改路径，这里用链接零配置。' }
    'pip-cache'    = @{ Src='C:\Users\76693\AppData\Local\pip';       Dst='G:\AI\data\pip-cache';
                        Note='pip 下载缓存（903 文件 / 554MB）。纯缓存，删了也只是重下。' }
    'uv-cache'     = @{ Src='C:\Users\76693\AppData\Local\uv';        Dst='G:\AI\data\uv-cache';
                        Note='uv 缓存（6.3k 文件 / 251MB）。' }
    'vscode-shared'= @{ Src='C:\Users\76693\.vscode-shared';          Dst='G:\AI\data\vscode-shared';
                        Note='VS Code 共享数据（2 文件）。' }
}

function Get-Stat([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $i = Get-Item -LiteralPath $p -Force
    if (-not $i.PSIsContainer) { return [pscustomobject]@{ Count=1; Bytes=[long]$i.Length } }
    $s = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    return [pscustomobject]@{ Count=[long]$s.Count; Bytes=[long]$s.Sum }
}

foreach ($name in $UNITS.Keys) {
    if ($Only -and $Only -ne $name) { continue }
    $u = $UNITS[$name]
    $src = $u.Src; $dst = $u.Dst
    Write-Host "`n=== $name ==="
    Write-Host "  $src"
    Write-Host "  -> $dst"
    Write-Host "  $($u.Note)"

    if (-not (Test-Path -LiteralPath $src)) { Write-Host "  源不存在，跳过。"; continue }
    $item = Get-Item -LiteralPath $src -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Write-Host "  已是链接，跳过。"; continue }

    $st = Get-Stat $src
    Write-Host ("  体积 {0:N0} 文件 / {1:N1} MB" -f $st.Count, ($st.Bytes/1MB))
    if ($Plan) { continue }

    if (-not (Test-Path -LiteralPath $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    $rcLog = Join-Path $LogDir ("reclaim-{0}-{1}.log" -f $name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $a = @("`"$src`"","`"$dst`"",'/E','/COPY:DAT','/DCOPY:DAT','/R:1','/W:1','/MT:16','/NFL','/NDL','/NP',"/LOG:`"$rcLog`"")
    $p = Start-Process robocopy.exe -ArgumentList ($a -join ' ') -Wait -PassThru -NoNewWindow
    Write-Host "  robocopy 退出码 $($p.ExitCode)"
    if ($p.ExitCode -ge 8) { Write-Host "  复制失败，跳过。"; continue }

    $dt = Get-Stat $dst
    Write-Host ("  校验 目标 {0:N0} / 源 {1:N0} -> {2}" -f $dt.Count, $st.Count, $(if($dt.Count -eq $st.Count){'一致'}else{'不一致'}))
    if ($dt.Count -ne $st.Count) { Write-Host "  校验不一致，中止（源未动）"; continue }

    $bk = Join-Path $BackupRoot ((Split-Path $src -Leaf) + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Write-Host "  源 -> 备份 $bk"
    $a = @("`"$src`"","`"$bk`"",'/MOV','/E','/R:1','/W:1','/MT:16','/NFL','/NDL','/NP')
    $p = Start-Process robocopy.exe -ArgumentList ($a -join ' ') -Wait -PassThru -NoNewWindow
    if (Test-Path -LiteralPath $src) { try { [System.IO.Directory]::Delete('\\?\'+$src,$true) } catch {} }
    if (Test-Path -LiteralPath $src) { Write-Host "  源未能清空，停止"; continue }

    $null = & cmd.exe /c mklink /J "$src" "$dst"
    $ni = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
    $isLink = $ni -and ($ni.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    $ck = Get-Stat $src
    Write-Host ("  链接={0}  通过链接可见 {1:N0} 文件（源 {2:N0}）" -f [bool]$isLink, $ck.Count, $st.Count)
    "{0}`t{1}`t{2}`t{3}" -f (Get-Date -Format s), $name, $src, $dst | Add-Content -LiteralPath (Join-Path $LogDir 'reclaim.tsv') -Encoding UTF8
}
Write-Host "`n完成。"
