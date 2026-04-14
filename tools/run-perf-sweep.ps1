[CmdletBinding()]
param(
    [switch]$KeepRawLog
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "sim_out\image_geo_top_perf_sweep"
$reportPath = Join-Path $repoRoot "docs\verification\perf_sweep_latest.md"
$rawLogPath = Join-Path $outDir "xsim.log"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Write-Host "== Running image_geo_top_perf_sweep =="
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run-module-sim.ps1") image_geo_top_perf_sweep | Out-Host

if (!(Test-Path $rawLogPath)) {
    throw "Missing perf sweep xsim log: $rawLogPath"
}

$perfLines = Select-String -Path $rawLogPath -Pattern '^PERF ' | ForEach-Object { $_.Line }
if ($perfLines.Count -eq 0) {
    throw "No PERF lines found in $rawLogPath"
}

$rows = foreach ($line in $perfLines) {
    $row = [ordered]@{}
    foreach ($token in ($line -split ' ' | Select-Object -Skip 1)) {
        if ($token -match '=') {
            $parts = $token -split '=', 2
            $row[$parts[0]] = $parts[1]
        }
    }
    [pscustomobject]$row
}

$report = @()
$report += "# Performance Sweep Report"
$report += ""
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += ""
$report += "| Case | Prefetch | Src | Dst | Reads | Misses | Prefetches | Hits |"
$report += "| --- | --- | --- | --- | ---: | ---: | ---: | ---: |"

foreach ($row in $rows) {
    $report += "| $($row.case) | $($row.prefetch) | $($row.src) | $($row.dst) | $($row.reads) | $($row.misses) | $($row.prefetches) | $($row.hits) |"
}

$report += ""
$report += "## Notes"
$report += ""
$report += "- `prefetch=0` is the baseline."
$report += "- `prefetch=1` enables the runtime tile-cache prefetch path."
$report += "- Compare `misses` and `hits` first when judging whether prefetch helps a case."

$report | Set-Content -Path $reportPath -Encoding utf8
Write-Host "Report written to $reportPath"

if (-not $KeepRawLog) {
    Write-Host "Raw log kept at $rawLogPath"
}
