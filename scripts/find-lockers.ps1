# scripts/find-lockers.ps1
# Generic lock investigation for target paths. No app names are hardcoded.
#
# Usage:
#   powershell -File find-lockers.ps1 -Path "C:\cache\dir1","C:\cache\dir2"
#   powershell -File find-lockers.ps1 -Path "C:\cache\dir" -ProbeFiles -MaxProbe 500
#
# What it checks (all generic, derived from the paths you pass in):
#   1. Services whose binary (PathName) lives under the target path
#   2. Processes whose executable (Path) lives under the target path
#   3. Processes whose command line references the target path (script hosts etc.)
#   4. Other powershell/pwsh sessions that might be cleanup tasks holding handles
#   5. Optional (-ProbeFiles): exclusive-open probing to list exactly which files are locked
param(
  [Parameter(Mandatory=$true)][string[]]$Path,
  [switch]$ProbeFiles,
  [int]$MaxProbe = 500
)

$ErrorActionPreference = 'SilentlyContinue'
function SizeMB($b) { [math]::Round($b / 1MB, 1) }

Write-Output "===== 1. services with binaries under target paths ====="
$svcHit = $false
foreach ($p in $Path) {
  Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
    $_.PathName -and $_.PathName.StartsWith($p, 'OrdinalIgnoreCase')
  } | ForEach-Object {
    $svcHit = $true
    Write-Output ("  {0}  [{1}]  {2}" -f $_.Name, $_.State, $_.PathName)
    Write-Output "    -> stop via: Stop-Service '<Name>' -Force (elevated), restart after cleanup"
  }
}
if (-not $svcHit) { Write-Output "  none" }

Write-Output ""
Write-Output "===== 2. processes with executables under target paths ====="
$procHit = $false
foreach ($p in $Path) {
  Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($p, 'OrdinalIgnoreCase') } |
    ForEach-Object {
      $procHit = $true
      Write-Output ("  {0} (pid {1})  {2}" -f $_.ProcessName, $_.Id, $_.Path)
    }
}
if (-not $procHit) { Write-Output "  none" }

Write-Output ""
Write-Output "===== 3. processes whose command line references target paths ====="
$cmdHit = $false
foreach ($p in $Path) {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and $_.CommandLine.IndexOf($p, 'OrdinalIgnoreCase') -ge 0
  } | ForEach-Object {
    $cmdHit = $true
    Write-Output ("  pid={0} [{1}]  {2}" -f $_.ProcessId, $_.Name, $_.CommandLine.Substring(0, [Math]::Min(140, $_.CommandLine.Length)))
  }
}
if (-not $cmdHit) { Write-Output "  none" }

Write-Output ""
Write-Output "===== 4. other powershell/pwsh sessions (possible cleanup tasks holding handles) ====="
$sh = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue
if ($sh) {
  $sh | ForEach-Object {
    Write-Output ("  pid={0}  {1}" -f $_.ProcessId, $_.CommandLine.Substring(0, [Math]::Min(140, $_.CommandLine.Length)))
  }
  Write-Output "  -> if any of these is an earlier cleanup run, let it finish or stop it, then retry"
} else { Write-Output "  none" }

Write-Output ""
Write-Output "===== 5. summary ====="
foreach ($p in $Path) {
  if (Test-Path -LiteralPath $p) {
    $f = Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue
    $sum = ($f | Measure-Object Length -Sum).Sum
    Write-Output ("  {0,10} MB  {1,6} files  {2}" -f (SizeMB $sum), $f.Count, $p)
  } else { Write-Output ("         gone         {0}" -f $p) }
}

if ($ProbeFiles) {
  Write-Output ""
  Write-Output "===== 6. locked-file probe (exclusive open test) ====="
  Write-Output "  locked files will fail a ReadWrite/None open; sharing conflicts = in use"
  $locked = 0; $probed = 0
  foreach ($p in $Path) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      if ($probed -ge $MaxProbe) { Write-Output "  (probe limit reached)"; break }
      $probed++
      try {
        $fs = [System.IO.File]::Open($f.FullName, 'Open', 'ReadWrite', 'None')
        $fs.Close()
      } catch [System.IO.IOException] {
        $locked++
        Write-Output ("  LOCKED  {0}" -f $f.FullName)
      } catch {
        # access denied etc. is a permission issue, not a lock - report separately
        Write-Output ("  NOACCESS {0}" -f $f.FullName)
      }
    }
  }
  Write-Output ("  probed={0} locked={1}" -f $probed, $locked)
}

Write-Output ""
Write-Output "TIP: for exact per-PID handle attribution use Sysinternals handle.exe, or"
Write-Output "Resource Monitor (resmon) > CPU tab > Associated Handles, searching the path."