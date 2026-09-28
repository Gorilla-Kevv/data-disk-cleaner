# scripts/recycle-stats.ps1
# Real recycle bin size per drive via SHQueryRecycleBin API
# Do NOT enumerate the recycle bin folder directly - SID subdir permissions break the walk and show 0.
$ErrorActionPreference = 'SilentlyContinue'
$codePath = Join-Path $PSScriptRoot 'recycle-bin-api.cs'
Add-Type -TypeDefinition (Get-Content -LiteralPath $codePath -Raw -Encoding UTF8) -ErrorAction Stop

Write-Output "===== RECYCLE BIN (per drive) ====="
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
  Write-Output ("{0}  {1}" -f $_.DeviceID, [RecycleStats]::Query($_.DeviceID))
}
Write-Output ""
Write-Output "NOTE: recycle bin content still occupies its original disk until emptied by the user."
