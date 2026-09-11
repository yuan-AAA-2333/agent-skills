#requires -Version 5.1
<#
  Move-CodeUnit.ps1 -- 代码迁移：把项目移到 G:\Code 分类目录，并在原位置留 junction。
  同盘(G:->G:)用 .NET 目录改名为原子瞬移；跨盘用 robocopy。
  校验：目标文件数 == 源文件数 才动源。
  用法:
    ... Move-CodeUnit.ps1 -List
    ... Move-CodeUnit.ps1 -Unit model-research -Mode Link
    ... Move-CodeUnit.ps1 -Unit model-research -Mode Copy
#>
[CmdletBinding()]
param([string]$Unit='',[ValidateSet('Copy','Link','List')][string]$Mode='Link')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root='E:\dsh\migration'; $LogDir="$Root\logs"; $BackupRoot='G:\AI\_backup'
foreach($d in @($LogDir,$BackupRoot)){ if(-not(Test-Path $d)){ New-Item -ItemType Directory $d -Force|Out-Null } }

$UNITS = [ordered]@{
    # ---- 01 科研 ----
    'ph Engle i-legacy' = @{ Src=''; Dst='' }   # 占位，忽略
    'aerospace-legacy'  = @{ Src='G:\Aerospace_Research_Institute';  Dst='G:\Code\01-科研\Aerospace-Research\legacy-project' }
    'aerospace-master'  = @{ Src='G:\Aerospace Research Institute';  Dst='G:\Code\01-科研\Aerospace-Research\master' }
    'radar-microwave'   = @{ Src='G:\项目雷达微波处理文件';                 Dst='G:\Code\01-科研\Radar-Microwave' }
    # ---- 02 竞赛 ----
    'modex'             = @{ Src='G:\AI\agents\modex\data';           Dst='G:\Code\02-竞赛\Modex-Agent-Workspace' }
    'math-modeling-research' = @{ Src='G:\Mathematical Modeling Research'; Dst='G:\Code\01-科研\Mathematical-Modeling-Research' }
    # ---- 03 课程作业 ----
    'learning'          = @{ Src='G:\learning';                      Dst='G:\Code\03-课程作业\pythonProject-learning' }
    'credit-scoring'    = @{ Src='C:\Users\76693\Desktop\大作业\credit_scoring'; Dst='G:\Code\03-课程作业\credit-scoring' }
    # ---- 04 工具与应用 ----
    'finance'           = @{ Src='G:\finance';                       Dst='G:\Code\04-工具与应用\Finance-Quant' }
    'lingxi'            = @{ Src='G:\LingXi';                        Dst='G:\Code\04-工具与应用\LingXi-NN' }
    'scratch-test'      = @{ Src='G:\test';                          Dst='G:\Code\04-工具与应用\scratch-test' }
    'pingdou-app'       = @{ Src='E:\文档\Kimi\Workspaces\pingdou tool\pingdou-app'; Dst='G:\Code\04-工具与应用\pingdou-app' }
    'project1'          = @{ Src='G:\code\Project1';                 Dst='G:\Code\04-工具与应用\Project1' }
    # ---- 05 教学与素材 ----
    'model-teaching'    = @{ Src='G:\Mathematical Modeling Research\数模模型代码与教学'; Dst='G:\Code\05-教学与素材\数模模型代码与教学' }
    # ---- 06 软著材料 ----
    'copyright-models'  = @{ Src='G:\Kimi_Agent_数模软著整理';              Dst='G:\Code\06-软著材料\qsl_os-suanzhu' }
    'copyright-full'    = @{ Src='G:\Kimi_Agent_软件著作前后端';            Dst='G:\Code\06-软著材料\qsl_os-fullstack' }
    # ---- 05 第三方源码 ----
    'thirdparty-phenglei' = @{ Src='G:\code\PHengLEI-master';  Dst='G:\Code\05-第三方源码\PHengLEI-master' }
    'thirdparty-cq08'     = @{ Src='G:\code\cq-08';            Dst='G:\Code\05-第三方源码\cq-08' }
    'thirdparty-wjx'      = @{ Src='G:\code\wjx';              Dst='G:\Code\05-第三方源码\wjx' }
    'thirdparty-code'     = @{ Src='G:\code';                  Dst='G:\Code\03-课程作业\_code-legacy-scratch' }
    'scratch-notebook'    = @{ Src='G:\test.ipynb';            Dst='G:\Code\04-工具与应用\scratch-test\test.ipynb' }
    'archive-latex'       = @{ Src='G:\code\1.tex';            Dst='G:\Code\09-归档\历史压缩包\1.tex' }
    # ---- 09 归档 ----
    'archive-model-zip' = @{ Src='G:\M7.8.2.zip';                    Dst='G:\Code\09-归档\历史压缩包\M7.8.2.zip' }
    'archive-model-dir' = @{ Src='G:\M7.8.2';                        Dst='G:\Code\09-归档\历史压缩包\M7.8.2' }
    'archive-mhagent'   = @{ Src='G:\MHAgent_A题_20260805_051310.zip'; Dst='G:\Code\09-归档\历史压缩包\MHAgent_A题_20260805_051310.zip' }
    'archive-notebook'  = @{ Src='G:\test.ipynb';                    Dst='G:\Code\04-工具与应用\scratch-test\test.ipynb' }
    'archive-zips-kimi' = @{ Src='G:\Kimi_Agent_数模软著整理.zip';          Dst='G:\Code\09-归档\历史压缩包\Kimi_Agent_数模软著整理.zip' }
    'archive-zips-kimi2'= @{ Src='G:\Kimi_Agent_软件著作前后端.zip';         Dst='G:\Code\09-归档\历史压缩包\Kimi_Agent_软件著作前后端.zip' }
    'archive-phenglei-zip' = @{ Src='G:\code\PHengLEI-master.zip';   Dst='G:\Code\09-归档\历史压缩包\PHengLEI-master.zip' }
}

function Get-Files($p){
    if(-not(Test-Path -LiteralPath $p)){ return [pscustomobject]@{Count=-1;MB=0} }
    $i=Get-Item -LiteralPath $p -Force
    if(-not $i.PSIsContainer){ return [pscustomobject]@{Count=1;MB=[math]::Round($i.Length/1MB,2)} }
    $s=Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    return [pscustomobject]@{Count=[long]$s.Count;MB=[math]::Round($s.Sum/1MB,2)}
}

if($Mode -eq 'List' -or $Unit -eq ''){
    "{0,-22} {1,-52} {2}" -f 'UNIT','SOURCE','TARGET' | Write-Host
    '-'*150 | Write-Host
    foreach($k in $UNITS.Keys){
        $u=$UNITS[$k]; if(-not $u.Src){continue}
        $ex = if(Test-Path -LiteralPath $u.Src){''}else{'  <-- 源不存在'}
        "{0,-22} {1,-52} {2}{3}" -f $k,$u.Src,$u.Dst,$ex | Write-Host
    }
    return
}
if(-not $UNITS.Contains($Unit)){ throw "未知单元 $Unit" }
$u=$UNITS[$Unit]; $src=$u.Src; $dst=$u.Dst
Write-Host "=== $Unit [$Mode] ==="
Write-Host "  $src"
Write-Host "  -> $dst"
if(-not(Test-Path -LiteralPath $src)){ throw "源不存在: $src" }
$si=Get-Item -LiteralPath $src -Force
if($si.Attributes -band [System.IO.FileAttributes]::ReparsePoint){ throw "源已是链接，跳过: $src" }

$st=Get-Files $src
Write-Host ("  体积 {0:N0} 文件 / {1:N1} MB" -f $st.Count,$st.MB)
$dstDir=Split-Path $dst -Parent
if(-not(Test-Path -LiteralPath $dstDir)){ New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
if(Test-Path -LiteralPath $dst){ throw "目标已存在，先人工处理: $dst" }

$isDir=$si.PSIsContainer
$sameVol = ($src.Substring(0,2).ToUpper() -eq $dst.Substring(0,2).ToUpper())

# ---------- 复制 ----------
if($sameVol){
    Write-Host "  [1/4] 同盘(G:)改用目录改名（瞬时、零拷贝）..."
    if($isDir){
        try { Move-Item -LiteralPath $src -Destination $dst -ErrorAction Stop }
        catch { [System.IO.Directory]::Move('\\?\'+$src,'\\?\'+$dst) }
    } else {
        try { Move-Item -LiteralPath $src -Destination $dst -ErrorAction Stop }
        catch { [System.IO.File]::Move('\\?\'+$src,'\\?\'+$dst) }
    }
    $rc=0
} else {
    Write-Host "  [1/4] 跨盘 robocopy 复制..."
    $rcLog="$LogDir\codecopy-$Unit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $a=@("`"$src`"","`"$dst`"",'/E','/COPY:DAT','/DCOPY:DAT','/R:1','/W:1','/MT:16','/NFL','/NDL','/NP',"/LOG:`"$rcLog`"")
    $p=Start-Process robocopy.exe -ArgumentList ($a -join ' ') -Wait -PassThru -NoNewWindow
    $rc=$p.ExitCode
    Write-Host "  robocopy 退出码 $rc  (日志 $rcLog)"
    if($rc -ge 8){ throw "robocopy 失败 $rc" }
}

# ---------- 校验 ----------
Write-Host "  [2/4] 校验..."
$dt=Get-Files $dst
$ok = ($dt.Count -eq $st.Count)
Write-Host ("  目标 {0:N0} 文件 / {1:N1} MB  vs 源 {2:N0} / {3:N1} MB  -> {4}" -f $dt.Count,$dt.MB,$st.Count,$st.MB,$(if($ok){'一致'}else{'不一致'}))
if(-not $ok){ throw "校验不一致，已中止（目标保留在 $dst，源未删）" }

if($Mode -eq 'Copy'){
    if($sameVol){ Move-Item -LiteralPath $dst -Destination $src }   # 同盘改名后要放回去
    Write-Host "  Copy 模式结束（源保持不动）。"
    return
}

# ---------- 移动源到备份 + 建 junction ----------
Write-Host "  [3/4] 源 -> 备份，并建立 junction..."
if(-not $sameVol){
    $bk="$BackupRoot\code-" + (Split-Path $src -Leaf) + '.' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    $mvLog="$LogDir\codemove-$Unit-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $a=@("`"$src`"","`"$bk`"",'/MOV','/E','/R:1','/W:1','/MT:16','/NFL','/NDL','/NP',"/LOG:`"$mvLog`"")
    $p=Start-Process robocopy.exe -ArgumentList ($a -join ' ') -Wait -PassThru -NoNewWindow
    if(Test-Path -LiteralPath $src){ try{ [System.IO.Directory]::Delete('\\?\'+$src,$true) }catch{} }
    if(Test-Path -LiteralPath $src){ throw "源未能清空，停止: $src" }
    Write-Host "  备份: $bk"
} else {
    Write-Host "  （同盘已直接改名，无需额外备份；G 盘本身就是主副本）"
}

if($isDir){
    $null = & cmd.exe /c mklink /J "$src" "$dst"
    $ni=Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
    if(-not $ni -or -not ($ni.Attributes -band [System.IO.FileAttributes]::ReparsePoint)){
        throw "junction 建立失败: $src -> $dst"
    }
    Write-Host "  [4/4] junction OK: $src -> $($ni.Target -join ',')"
    $ck=Get-Files $src
    if($ck.Count -ne $st.Count){ throw "通过链接可见文件数不符: $($ck.Count) != $($st.Count)" }
    Write-Host ("  通过链接可见 {0:N0} 文件 / {1:N1} MB —— 一致" -f $ck.Count,$ck.MB)
} else {
    # 单文件：已复制到新位置并删源，不做链接（文件级链接跨盘不可用）
    if(Test-Path -LiteralPath $src){ Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue }
    Write-Host "  [4/4] 单文件已迁移（无链接）: $dst"
}
"{0}`t{1}`t{2}`t{3}" -f (Get-Date -Format s),$Unit,$src,$dst | Add-Content -LiteralPath "$LogDir\code-migration.tsv" -Encoding UTF8
