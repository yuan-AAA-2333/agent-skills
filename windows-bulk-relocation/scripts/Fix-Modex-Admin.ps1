# ============================================================================
#  Fix-Modex-Admin.ps1  --  需要管理员权限
#  作用：把 E:\modex 的【源目录】彻底删除，并在原位置建立指向 G:\AI\apps\modex
#        的目录联接（junction），使所有旧快捷方式/配置继续可用。
#
#  前提（已由 AI 校验）：G:\AI\apps\modex 与 E:\modex 内容完全一致
#        （83,701 个文件 / 7,287.2 MB），且 G:\AI\_backup\modex.final-* 另有一份备份。
#
#  用法：双击 Run-Fix-Modex.cmd（会自动弹 UAC 请求管理员权限）
# ============================================================================
$ErrorActionPreference = 'Stop'

$SRC = 'E:\modex'
$DST = 'G:\AI\apps\modex'

function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object System.Security.Principal.WindowsPrincipal $id).IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "需要管理员权限，正在重新启动（请在弹出的 UAC 窗口点『是』）..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File', ('"{0}"' -f $PSCommandPath)
    )
    exit
}

Write-Host "已获得管理员权限。" -ForegroundColor Green

if (-not (Test-Path -LiteralPath $DST)) { throw "目标不存在：$DST —— 中止" }
$dstStat = Get-ChildItem -LiteralPath $DST -Recurse -File -Force -ErrorAction SilentlyContinue |
           Measure-Object Length -Sum
Write-Host ("目标副本: {0:N0} 文件 / {1:N1} MB" -f $dstStat.Count, ($dstStat.Sum/1MB))

if (-not (Test-Path -LiteralPath $SRC)) {
    Write-Host "源已不存在，直接建链接。"
} elseif ((Get-Item -LiteralPath $SRC -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    Write-Host "源已经是链接，无需处理。"
    exit
} else {
    $srcStat = Get-ChildItem -LiteralPath $SRC -Recurse -File -Force -ErrorAction SilentlyContinue |
               Measure-Object Length -Sum
    Write-Host ("源目录  : {0:N0} 文件 / {1:N1} MB" -f $srcStat.Count, ($srcStat.Sum/1MB))
    if ($srcStat.Count -ne $dstStat.Count) {
        throw "源与目标文件数不一致，为安全起见中止。请人工核对。"
    }

    Write-Host "`n[1/3] 取得所有权 ..." -ForegroundColor Cyan
    & takeown.exe /f $SRC /r /d y 2>&1 | Select-Object -Last 3
    Write-Host "[2/3] 授予当前用户完全控制 ..." -ForegroundColor Cyan
    $me = "$env:USERDOMAIN\$env:USERNAME"
    & icacls.exe $SRC /grant "${me}:(F)" /t /c /q 2>&1 | Select-Object -Last 3

    Write-Host "[3/3] 删除源目录（内容已在 G 盘，删除只影响重复副本）..." -ForegroundColor Cyan
    & cmd.exe /c rmdir /s /q "$SRC"
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $SRC) {
        try { [System.IO.Directory]::Delete('\\?\' + $SRC, $true) } catch {
            Write-Host "  仍无法删除：$($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  请手动删除 E:\modex 后重新运行本脚本（会自动跳到建链接）。" -ForegroundColor Yellow
            Read-Host "按回车退出"
            exit 1
        }
    }
    Write-Host "  源目录已删除。" -ForegroundColor Green
}

Write-Host "`n建立目录联接: $SRC  ->  $DST" -ForegroundColor Cyan
$null = & cmd.exe /c mklink /J "$SRC" "$DST"
$item = Get-Item -LiteralPath $SRC -Force -ErrorAction SilentlyContinue
if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    $chk = Get-ChildItem -LiteralPath $SRC -Recurse -File -Force -ErrorAction SilentlyContinue |
           Measure-Object Length -Sum
    Write-Host ("完成。E:\modex 现在指向 G 盘，通过它可见 {0:N0} 个文件 / {1:N1} MB" -f $chk.Count, ($chk.Sum/1MB)) -ForegroundColor Green
    Write-Host "Modex 可以照常从原快捷方式启动。"
} else {
    Write-Host "建立联接失败，请人工处理。" -ForegroundColor Red
}
Read-Host "`n按回车关闭"
