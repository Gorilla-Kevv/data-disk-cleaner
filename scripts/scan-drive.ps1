# scripts/scan-drive.ps1
# Parameterized read-only scan for a DATA drive. Single-pass enumeration, multi-bucket stats.
# Usage: powershell -File scan-drive.ps1 -Drive F: [-OldDays 180] [-BigFileGB 1] [-TopN 20]
param(
  [Parameter(Mandatory=$true)][string]$Drive,
  [int]$OldDays = 180,
  [double]$BigFileGB = 1,
  [int]$TopN = 20
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
function SizeGB($b) { [math]::Round($b / 1GB, 2) }

$root = $Drive.TrimEnd('\')
if ($root -notmatch '^[A-Za-z]:$') { Write-Output "INVALID DRIVE: $Drive (expected like F:)"; exit 1 }
$bigBytes = $BigFileGB * 1GB
$cut = (Get-Date).AddDays(-$OldDays)
$pkgExt = @('.zip','.7z','.rar','.iso','.exe','.msi','.gz','.tar','.xz')
$vmExt  = @('.vhdx','.vhd','.vmdk','.vdi','.qcow2','.img')
$garbageNames = @('node_modules','target','dist','build','out','obj','__pycache__','.venv','venv','.pytest_cache','.next','.nuxt')

# ---- single pass over all files ----
Write-Output "enumerating $root ... (single pass, may take a while on HDD)"
$installers = @(); $vmDisks = @(); $bigFiles = @(); $oldFiles = @()
$dirAgg = @{}
$garbageAgg = @{}
$count = 0
foreach ($f in [System.IO.Directory]::EnumerateFiles("$root\", '*', [System.IO.SearchOption]::AllDirectories)) {
    $count++
    try {
        $fi = [System.IO.FileInfo]::new($f)
        $len = $fi.Length
        $top = $f.Substring($root.Length + 1).Split('\')[0]
        if (-not $dirAgg.ContainsKey($top)) { $dirAgg[$top] = [System.Tuple]::Create(0L, 0) }
        $old = $dirAgg[$top]
        $dirAgg[$top] = [System.Tuple]::Create($old.Item1 + $len, $old.Item2 + 1)

        $ext = $fi.Extension.ToLower()
        if ($len -gt 100MB -and ($pkgExt -contains $ext)) { $installers += $fi }
        if ($vmExt -contains $ext) { $vmDisks += $fi }
        if ($len -gt $bigBytes) { $bigFiles += $fi }
        if ($fi.LastWriteTime -lt $cut -and $len -gt 100MB) { $oldFiles += $fi }
    } catch {}
}

# ---- single pass over all dirs for build garbage ----
$garbageDirs = @()
foreach ($d in [System.IO.Directory]::EnumerateDirectories("$root\", '*', [System.IO.SearchOption]::AllDirectories)) {
    $name = [System.IO.Path]::GetFileName($d)
    if ($garbageNames -contains $name) { $garbageDirs += $d }
}
$garbageSizes = @{}
foreach ($g in $garbageDirs) { $garbageSizes[$g] = 0L }
foreach ($f in [System.IO.Directory]::EnumerateFiles("$root\", '*', [System.IO.SearchOption]::AllDirectories)) {
    try {
        $parent = [System.IO.Path]::GetDirectoryName($f)
        if ($garbageSizes.ContainsKey($parent)) { $garbageSizes[$parent] += ([System.IO.FileInfo]::new($f)).Length }
    } catch {}
}

$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$root'"
Write-Output ("===== DRIVE {0}  Total {1} GB  Free {2} GB  ({3} files enumerated) =====" -f $d.DeviceID, (SizeGB $d.Size), (SizeGB $d.FreeSpace), $count)

Write-Output ""
Write-Output "===== 1. TOP DIRS ====="
$dirAgg.GetEnumerator() | Sort-Object Value.Item1 -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Output ("  {0,8} GB  {1,7} files  {2}" -f (SizeGB $_.Value.Item1), $_.Value.Item2, $_.Key)
}

Write-Output ""
$gTotal = ($garbageSizes.Values | Measure-Object -Sum).Sum
Write-Output ("===== 2. BUILD GARBAGE (total {0} GB in {1} dirs) =====" -f (SizeGB $gTotal), $garbageSizes.Count)
$garbageSizes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Output ("  {0,8} GB  {1}" -f (SizeGB $_.Value), $_.Key)
}

Write-Output ""
Write-Output "===== 3. INSTALLERS / ARCHIVES >100MB (check if already extracted) ====="
$installers | Sort-Object Length -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Output ("  {0,8} GB  {1}  {2}" -f (SizeGB $_.Length), $_.LastWriteTime.ToString('yyyy-MM-dd'), $_.FullName)
}

Write-Output ""
Write-Output "===== 4. VIRTUAL MACHINE DISKS (report only, never delete) ====="
$vmDisks | Sort-Object Length -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Output ("  {0,8} GB  {1}  {2}" -f (SizeGB $_.Length), $_.LastWriteTime.ToString('yyyy-MM-dd'), $_.FullName)
}

Write-Output ""
Write-Output "===== 5. BIG FILES >$BigFileGB GB ====="
$bigFiles | Sort-Object Length -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Output ("  {0,8} GB  {1}  {2}" -f (SizeGB $_.Length), $_.LastWriteTime.ToString('yyyy-MM-dd'), $_.FullName)
}

Write-Output ""
Write-Output "===== 6. OLD FILES >$OldDays DAYS (>100MB, top by size) ====="
$oldFiles | Sort-Object Length -Descending | Select-Object -First $TopN | ForEach-Object {
    Write-Output ("  {0,8} GB  {1}  {2}" -f (SizeGB $_.Length), $_.LastWriteTime.ToString('yyyy-MM-dd'), $_.FullName)
}

Write-Output ""
Write-Output "===== 7. RECYCLE BIN ON THIS DRIVE ====="
$codePath = Join-Path $PSScriptRoot 'recycle-bin-api.cs'
if (Test-Path -LiteralPath $codePath) {
    Add-Type -TypeDefinition (Get-Content -LiteralPath $codePath -Raw -Encoding UTF8) -ErrorAction Stop
    Write-Output ("  {0} recycle bin: {1}" -f $root, [RecycleBinApi]::Query($root))
}

Write-Output ""
Write-Output "NOTE: strictly read-only scan. Nothing was moved or deleted."