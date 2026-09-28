# scripts/clean-batch.ps1
# Batch move-to-recycle-bin: quota check + SHFileOperation bulk + locked-file isolation
# Usage: powershell -File clean-batch.ps1 -Manifest clean.json
# clean.json: { "targets": [ { "path": "...", "name": "...", "level": "green" } ] }
param([Parameter(Mandatory=$true)][string]$Manifest)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
function SizeGB($b) { [math]::Round($b / 1GB, 2) }

# --- 0. raise recycle bin quota (prevent silent permanent deletion) ---
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume' |
  ForEach-Object {
    Set-ItemProperty $_.PSPath -Name MaxCapacity -Value 102400 -Type DWord
    Set-ItemProperty $_.PSPath -Name NukeOnDelete -Value 0 -Type DWord
  }
Write-Output "[quota] recycle bin capacity raised to 100 GB on all volumes"

# --- 1. SHFileOperation P/Invoke ---
$sig = @'
using System;
using System.Runtime.InteropServices;
public class CleanBatch {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct SHFILEOPSTRUCT {
    public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo;
    public ushort fFlags; public int fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
  }
  [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
  public static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);
  public static int SendBatch(string[] paths) {
    var op = new SHFILEOPSTRUCT();
    op.wFunc = 3;
    op.pFrom = string.Join(",", paths) + ",";
    op.pFrom = op.pFrom.Replace(",", "\0");
    op.fFlags = 0x0040 | 0x0010 | 0x0400 | 0x0200;
    op.fAnyOperationsAborted = 0; op.hNameMappings = IntPtr.Zero; op.lpszProgressTitle = "";
    return SHFileOperation(ref op);
  }
}
'@
Add-Type -TypeDefinition $sig -ErrorAction Stop

function Send-Batch([string[]]$paths) {
  $ok = 0; $fail = 0; $failedPaths = @()
  for ($i = 0; $i -lt $paths.Count; $i += 200) {
    $end = [Math]::Min($i + 199, $paths.Count - 1)
    $chunk = @()
    for ($j = $i; $j -le $end; $j++) { $chunk += $paths[$j] }
    if ($chunk.Count -eq 0) { continue }
    $rc = [CleanBatch]::SendBatch($chunk)
    if ($rc -eq 0) { $ok += $chunk.Count }
    else {
      foreach ($p in $chunk) {
        $rc2 = [CleanBatch]::SendBatch(@($p))
        if ($rc2 -eq 0) { $ok++ } else { $fail++; $failedPaths += $p }
      }
    }
  }
  return @($ok, $fail, $failedPaths)
}

# --- 2. process manifest ---
$manifest = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$free0 = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
Write-Output ("FREE BEFORE: {0} GB  (recycle bin items still occupy the same disk)" -f (SizeGB $free0))

$totalMoved = 0; $totalLocked = 0
foreach ($t in $manifest.targets) {
  if (-not (Test-Path -LiteralPath $t.path)) { Write-Output ("SKIP(missing)  {0}" -f $t.name); continue }
  $files = @(Get-ChildItem -LiteralPath $t.path -Recurse -File -Force -ErrorAction SilentlyContinue)
  $sz = ($files | Measure-Object Length -Sum).Sum
  if ($files.Count -eq 0) { Write-Output ("SKIP(empty)    {0}" -f $t.name); continue }

  $paths = @($files | Select-Object -ExpandProperty FullName)
  $r = Send-Batch $paths
  Start-Sleep -Milliseconds 200
  $totalMoved += $r[0]; $totalLocked += $r[1]
  $status = if ($r[1] -eq 0) { 'CLEARED' } else { 'PARTIAL' }
  Write-Output ("{0,-8} {1,8} GB  moved={2} locked={3}   {4}" -f $status, (SizeGB $sz), $r[0], $r[1], $t.name)
  if ($r[1] -gt 0) {
    Write-Output "  locked by running apps/services - close them and re-run, or elevate:"
    $r[2] | Select-Object -First 5 | ForEach-Object { Write-Output ("    " + $_) }
  }
}

Write-Output ""
Write-Output ("TOTAL: moved={0} locked={1}" -f $totalMoved, $totalLocked)
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
Write-Output ("FREE AFTER: {0} GB" -f (SizeGB $d.FreeSpace))
Write-Output "NOTE: files sit in the Recycle Bin until the user empties it manually."
