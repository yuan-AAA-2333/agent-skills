#requires -Version 5.1
<#
  Get-CodeInventory.ps1 -- read-only scan: find user code projects on all drives and classify them.
  Output: E:\dsh\migration\manifests\code-inventory.csv  (+ printed summary)
  PS 5.1 only. Uses compiled .NET enumerators (fast), tolerates access errors, skips reparse points.
#>
[CmdletBinding()]
param(
    [int]$MaxDepth = 6,
    [string]$Out = 'E:\dsh\migration\manifests\code-inventory.csv'
)
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Roots = @('C:\Users\76693','D:\','E:\','F:\','G:\')
$SkipNames = @('$RECYCLE.BIN','System Volume Information','Windows','WinSxS','WindowsApps','WpSystem',
               'node_modules','.git','.svn','.hg','miniconda3','anaconda3','pkgs','envs','AppData',
               'texlive','$SysReset','Config.Msi','Recovery','ProgramData','Program Files','Program Files (x86)',
               '.vscode','.cache','.npm','npm-cache','$WinREAgent','System32','Installer','Packages',
               '.gradle','.m2','.nuget','site-packages','__pycache__','.venv','venv','.conda')
# markers that mean "this directory is (part of) a project"
$Markers = @('.git','.idea','package.json','requirements.txt','pyproject.toml','pom.xml','build.gradle',
             'CMakeLists.txt','environment.yml','.sln','Cargo.toml','go.mod','setup.py','Pipfile','.project')
# markers that mean "this is a sub-folder of a project, not a root"
$SubMarkers = @('.vscode','.idea')
# heavy dirs excluded from size accounting
$HeavyDirs = @('node_modules','.git','.venv','venv','envs','__pycache__','.idea','.mypy_cache','.pytest_cache',
               'dist','build','.next','target','site-packages','pkgs','wheels')
$CodeExt = @('.py','.ipynb','.js','.ts','.tsx','.jsx','.m','.cpp','.c','.h','.hpp','.java','.cs','.go','.rs',
             '.r','.m','.jl','.sh','.ps1','.bat','.cmd','.sql','.html','.css','.vue','.f90','.f','.cu','.xml','.yaml','.yml')

function Get-DirInfo {
    param([string]$Path)
    $di = New-Object System.IO.DirectoryInfo $Path
    $rows = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Stack
    $stack.Push($di)
    $codeFiles=0; $allFiles=0; $codeBytes=[long]0; $allBytes=[long]0; $newest=[datetime]'1900-01-01'
    $langCount = @{}
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $items = $null
        try { $items = $cur.GetFileSystemInfos() } catch { continue }
        foreach ($it in $items) {
            if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($it -is [System.IO.DirectoryInfo]) {
                if ($SkipNames -contains $it.Name) { continue }
                $stack.Push($it)
            } else {
                $fi = [System.IO.FileInfo]$it
                $allFiles++; $allBytes += $fi.Length
                if ($fi.LastWriteTime -gt $newest) { $newest = $fi.LastWriteTime }
                $e = $fi.Extension.ToLower()
                if ($CodeExt -contains $e) {
                    $codeFiles++; $codeBytes += $fi.Length
                    if ($langCount.ContainsKey($e)) { $langCount[$e] = $langCount[$e] + 1 } else { $langCount[$e] = 1 }
                }
            }
        }
    }
    $top = ($langCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 4 |
            ForEach-Object { "$($_.Key):$($_.Value)" }) -join ' '
    return [pscustomobject]@{
        AllFiles=$allFiles; AllBytes=$allBytes; CodeFiles=$codeFiles; CodeBytes=$codeBytes
        Newest=$newest; Langs=$top
    }
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($root in $Roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Write-Host "scanning $root ..."
    $baseDepth = ($root.TrimEnd('\').Split('\')).Count
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $di = $null
        try { $di = New-Object System.IO.DirectoryInfo $cur } catch { continue }
        $items = $null
        try { $items = $di.GetFileSystemInfos() } catch { continue }
        $names = @(); $isDirMap = @{}
        foreach ($it in $items) {
            if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            $names += $it.Name
            $isDirMap[$it.Name] = ($it -is [System.IO.DirectoryInfo])
        }
        $hit = @($names | Where-Object { $Markers -contains $_ })
        if ($hit.Count -gt 0) {
            # decide root vs sub
            $strong = @($hit | Where-Object { $SubMarkers -notcontains $_ })
            $kind = if ($strong.Count -gt 0) { 'ROOT' } else { 'SUB' }
            $info = Get-DirInfo -Path $cur
            $results.Add([pscustomobject]@{
                Kind=$kind; Path=$cur; Markers=($hit -join '|')
                AllFiles=$info.AllFiles; AllMB=[math]::Round($info.AllBytes/1MB,1)
                CodeFiles=$info.CodeFiles; CodeMB=[math]::Round($info.CodeBytes/1MB,1)
                Newest=$info.Newest.ToString('yyyy-MM-dd'); Langs=$info.Langs
            })
        }
        $depth = ($cur.TrimEnd('\').Split('\')).Count - $baseDepth
        if ($depth -lt $MaxDepth) {
            foreach ($n in $names) {
                if (-not $isDirMap[$n]) { continue }
                if ($SkipNames -contains $n) { continue }
                $stack.Push((Join-Path $cur $n))
            }
        }
    }
}

$results | Sort-Object -Property @{Expression='Kind';Descending=$false}, @{Expression='CodeMB';Descending=$true} |
    Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host ""
Write-Host "TOTAL candidates: $($results.Count)  (ROOT $(@($results|Where-Object Kind -eq 'ROOT').Count) / SUB $(@($results|Where-Object Kind -eq 'SUB').Count))"
Write-Host "saved: $Out"
$results | Where-Object Kind -eq 'ROOT' | Sort-Object CodeMB -Descending | Select-Object -First 40 |
    Format-Table -AutoSize Path,Markers,CodeFiles,CodeMB,AllMB,Newest
