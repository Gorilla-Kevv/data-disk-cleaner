<#
.SYNOPSIS
    数据盘空间结构深度分析：单遍枚举全盘文件，按目录层级（Level 1..N）聚合体积。
.DESCRIPTION
    用途：用户问"这个盘为什么这么大 / 看看文件结构 / 空间大头在哪"时使用。
    与 scan-drive.ps1 互补：scan-drive 的 Top 目录清单存在截断/遗漏可能（实测曾漏掉
    SteamLibrary 102GB、[others] 102GB 等最大目录），本脚本按前缀分组聚合，保证完整。
    只读，不修改任何文件。
    兼容 Windows PowerShell 5.1（不用三元运算符等新语法）。
.EXAMPLE
    powershell -File scripts/scan-structure.ps1 -Drive D:
    powershell -File scripts/scan-structure.ps1 -Drive F: -MaxDepth 4 -MinGB 0.5 -TopN 60
#>
param(
    [string]$Drive = 'D:',
    [int]$MaxDepth = 3,
    [double]$MinGB = 1,
    [int]$TopN = 40
)

$ErrorActionPreference = 'SilentlyContinue'
$root = $Drive.TrimEnd('\') + '\'
$minBytes = $MinGB * 1GB

Write-Host ("Enumerating {0} ... (single pass, may take a while on HDD)" -f $root)
$all = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\(\$RECYCLE\.BIN|System Volume Information)\\' }

$totalGB = ($all | Measure-Object Length -Sum).Sum / 1GB
$driveLetter = $root.Substring(0, 1)
$freeGB = (Get-PSDrive $driveLetter).Free / 1GB
Write-Host ("===== DRIVE {0}  Files-total {1:N2} GB  Free {2:N2} GB  ({3} files) =====" -f $root, $totalGB, $freeGB, @($all).Count)

for ($depth = 1; $depth -le $MaxDepth; $depth++) {
    Write-Host ""
    Write-Host ("===== LEVEL {0} (> {1} GB, top {2}) =====" -f $depth, $MinGB, $TopN)
    $agg = @{}
    foreach ($f in $all) {
        $p = $f.FullName -split '\\'
        if ($p.Count -ge ($depth + 1)) {
            $key = $p[0..$depth] -join '\'
            if (-not $agg.ContainsKey($key)) { $agg[$key] = 0 }
            $agg[$key] += $f.Length
        }
        elseif ($depth -eq 1 -and $p.Count -eq 2) {
            # 根目录散落文件（如 pagefile.sys）单独成行
            if (-not $agg.ContainsKey($f.FullName)) { $agg[$f.FullName] = 0 }
            $agg[$f.FullName] += $f.Length
        }
    }
    $agg.GetEnumerator() |
        Where-Object { $_.Value -ge $minBytes } |
        Sort-Object Value -Descending |
        Select-Object -First $TopN |
        ForEach-Object { '{0,10:N2} GB  {1}' -f ($_.Value / 1GB), $_.Key }
}
