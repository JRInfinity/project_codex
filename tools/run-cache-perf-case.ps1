[CmdletBinding()]
param(
    [string]$Top = "tb_image_geo_top_perf_single_1000_600_downscale_on",
    [string]$RunName = "",

    [int]$CompileTimeoutSec = 300,
    [int]$ElabTimeoutSec = 300,
    [int]$SimTimeoutSec = 900,

    [int]$TileW = 64,
    [int]$TileH = 8,
    [int]$TileNum = 24,
    [int]$LeadPixels = 64,
    [int]$AnalyticFifoDepth = 32,
    [int]$BaseTileW = 8,
    [int]$BaseTileH = 8,
    [int]$SectorSetNum = 64,
    [int]$SectorWayNum = 4,
    [int]$MergeMaxX = 8,
    [int]$EnableMergeMin = 0,
    [int]$MergeMinX = 1,
    [int]$FifoAgeLimit = 0,
    [int]$EnablePrefetchThrottle = 0,
    [int]$PrefetchThrottleCycles = 0,
    [int]$EnableRowBucketMerge = 0,
    [int]$RowBucketMinX = 3,
    [int]$RuntimeLeadPixels = -1,
    [int]$RuntimeMergeMaxX = -1,
    [int]$RuntimeMergeMinX = -1,
    [int]$RuntimeFifoDepth = -1,
    [int]$RuntimeFifoAgeLimit = -1,
    [int]$RuntimePrefetchThrottleCycles = -1,
    [int]$RuntimeSchedulerPolicy = -1,
    [int]$RdBurstMaxLen = 16,
    [int]$RdMaxOutstandingBursts = 4,
    [int]$RdMaxOutstandingBeats = 16,
    [int]$RdFifoDepthWords = 64,
    [int]$WrBurstMaxLen = 16,
    [int]$WrFifoDepthPixels = 256,

    [switch]$FullProfile,
    [switch]$TbOnlyCompile,
    [switch]$CompileOnly,
    [switch]$ElabOnly,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RunName)) {
    $RunName = $Top
}

$safeRunName = ($RunName -replace '[^A-Za-z0-9_.-]', '_')
$outDir = Join-Path $repoRoot (Join-Path "sim_out" (Join-Path "cache_perf" $safeRunName))
if ($Clean -and (Test-Path $outDir)) {
    Remove-Item -LiteralPath $outDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$perfTbSource = if ($FullProfile) {
    "rtl/sim/tb_image_geo_top_perf_single_case.sv"
} else {
    "rtl/sim/tb_image_geo_top_perf_single_light.sv"
}

$compileLog = Join-Path $outDir "xvlog.log"
$elabLog = Join-Path $outDir "xelab.log"
$simLog = Join-Path $outDir "xsim.log"
$summaryPath = Join-Path $outDir "summary.txt"
$definesPath = Join-Path $outDir "cache_perf_defines.sv"
$snapshot = "${safeRunName}_snap"

function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)

    $items = @()
    foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') {
            $escaped = $arg -replace '"', '\"'
            $items += '"' + $escaped + '"'
        } else {
            $items += $arg
        }
    }
    return ($items -join ' ')
}

function Stop-XsimProcesses {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "xsim*" -or $_.ProcessName -like "xelab*" -or $_.ProcessName -like "xvlog*"
    }
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ToolWithTimeout {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSec,
        [string]$LogPath
    )

    Write-Host ">> $FilePath $($Arguments -join ' ')"
    $resolvedPath = (Get-Command $FilePath -ErrorAction Stop).Source
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedPath
    $psi.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $done = $false
    for ($i = 0; $i -lt $TimeoutSec; $i++) {
        $proc.Refresh()
        if ($proc.HasExited) {
            $done = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $done) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Stop-XsimProcesses
        if ($LogPath -and (Test-Path $LogPath)) {
            Get-Content $LogPath -Tail 80 | Out-Host
        }
        throw "Command timed out after ${TimeoutSec}s: $FilePath $($Arguments -join ' ')"
    }

    if ($proc.ExitCode -ne 0) {
        if ($LogPath -and (Test-Path $LogPath)) {
            Get-Content $LogPath -Tail 80 | Out-Host
        }
        throw "$FilePath exited with code $($proc.ExitCode). See log: $LogPath"
    }
}

$sources = @(
    "axi/rtl/taxi_axi_if.sv",
    "rtl/axi/ddr_axi_pkg.sv",
    "rtl/axi/reset_sync.sv",
    "rtl/axi/task_cdc.sv",
    "rtl/axi/task_cdc_2d.sv",
    "rtl/axi/result_cdc.sv",
    "rtl/axi/frame_config_cdc.sv",
    "rtl/axi/cache_stats_cdc.sv",
    "rtl/axi/axi_burst_reader.sv",
    "rtl/buffer/async_word_fifo.sv",
    "rtl/core/pixel_packer.sv",
    "rtl/core/pixel_unpacker.sv",
    "rtl/core/rotate_geom_init_unit.sv",
    "rtl/axi/ddr_read_engine.sv",
    "rtl/axi/ddr_write_engine.sv",
    "rtl/buffer/src_tile_cache.sv",
    "rtl/buffer/row_out_buffer.sv",
    "rtl/core/row_advance_unit.sv",
    "rtl/core/rotate_core_bilinear.sv",
    "rtl/ctrl/scaler_ctrl.sv",
    "rtl/top/image_geo_top.sv",
    $perfTbSource
)
if ($TbOnlyCompile) {
    $sources = @(
        $perfTbSource
    )
}

if ($RuntimeLeadPixels -lt 0) { $RuntimeLeadPixels = $LeadPixels }
if ($RuntimeMergeMaxX -lt 0) { $RuntimeMergeMaxX = $MergeMaxX }
if ($RuntimeMergeMinX -lt 0) { $RuntimeMergeMinX = $MergeMinX }
if ($RuntimeFifoDepth -lt 0) { $RuntimeFifoDepth = $AnalyticFifoDepth }
if ($RuntimeFifoAgeLimit -lt 0) { $RuntimeFifoAgeLimit = $FifoAgeLimit }
if ($RuntimePrefetchThrottleCycles -lt 0) { $RuntimePrefetchThrottleCycles = $PrefetchThrottleCycles }
if ($RuntimeSchedulerPolicy -lt 0) {
    $RuntimeSchedulerPolicy = 0
    if ($EnableMergeMin -ne 0) { $RuntimeSchedulerPolicy = $RuntimeSchedulerPolicy -bor 1 }
    if ($EnablePrefetchThrottle -ne 0) { $RuntimeSchedulerPolicy = $RuntimeSchedulerPolicy -bor 2 }
}

$defineLines = @(
    "// Generated by tools/run-cache-perf-case.ps1",
    "``define IMAGE_GEO_SRC_TILE_W $TileW",
    "``define IMAGE_GEO_SRC_TILE_H $TileH",
    "``define IMAGE_GEO_SRC_TILE_NUM $TileNum",
    "``define SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS $LeadPixels",
    "``define SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH $AnalyticFifoDepth",
    "``define SRC_TILE_CACHE_BASE_TILE_W $BaseTileW",
    "``define SRC_TILE_CACHE_BASE_TILE_H $BaseTileH",
    "``define SRC_TILE_CACHE_SECTOR_SET_NUM $SectorSetNum",
    "``define SRC_TILE_CACHE_SECTOR_WAY_NUM $SectorWayNum",
    "``define SRC_TILE_CACHE_MERGE_MAX_X $MergeMaxX",
    "``define SRC_TILE_CACHE_ENABLE_MERGE_MIN $EnableMergeMin",
    "``define SRC_TILE_CACHE_MERGE_MIN_X $MergeMinX",
    "``define SRC_TILE_CACHE_FIFO_AGE_LIMIT $FifoAgeLimit",
    "``define SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE $EnablePrefetchThrottle",
    "``define SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES $PrefetchThrottleCycles",
    "``define SRC_TILE_CACHE_ENABLE_ROW_BUCKET_MERGE $EnableRowBucketMerge",
    "``define SRC_TILE_CACHE_ROW_BUCKET_MIN_X $RowBucketMinX",
    "``define IMAGE_GEO_RUNTIME_LEAD_PIXELS $RuntimeLeadPixels",
    "``define IMAGE_GEO_RUNTIME_MERGE_MAX_X $RuntimeMergeMaxX",
    "``define IMAGE_GEO_RUNTIME_MERGE_MIN_X $RuntimeMergeMinX",
    "``define IMAGE_GEO_RUNTIME_FIFO_DEPTH $RuntimeFifoDepth",
    "``define IMAGE_GEO_RUNTIME_FIFO_AGE_LIMIT $RuntimeFifoAgeLimit",
    "``define IMAGE_GEO_RUNTIME_PREFETCH_THROTTLE_CYCLES $RuntimePrefetchThrottleCycles",
    "``define IMAGE_GEO_RUNTIME_SCHEDULER_POLICY $RuntimeSchedulerPolicy",
    "``define IMAGE_GEO_RD_BURST_MAX_LEN $RdBurstMaxLen",
    "``define IMAGE_GEO_RD_MAX_OUTSTANDING_BURSTS $RdMaxOutstandingBursts",
    "``define IMAGE_GEO_RD_MAX_OUTSTANDING_BEATS $RdMaxOutstandingBeats",
    "``define IMAGE_GEO_RD_FIFO_DEPTH_WORDS $RdFifoDepthWords",
    "``define IMAGE_GEO_WR_BURST_MAX_LEN $WrBurstMaxLen",
    "``define IMAGE_GEO_WR_FIFO_DEPTH_PIXELS $WrFifoDepthPixels"
)
if (-not $FullProfile) {
    $defineLines += "``define IMAGE_GEO_PERF_SINGLE_LIGHTWEIGHT 1"
}
Set-Content -Path $definesPath -Value $defineLines

$compileArgs = @("-sv", "-work", "xil_defaultlib", $definesPath)
foreach ($src in $sources) {
    $compileArgs += (Join-Path $repoRoot $src)
}
$compileArgs += @("--log", $compileLog)

$profileMode = if ($FullProfile) { "full" } else { "lightweight" }
$compileMode = if ($TbOnlyCompile) { "tb_only" } else { "full_sources" }
$paramLine = "top=$Top tile=${TileW}x${TileH} tile_num=$TileNum lead=$LeadPixels fifo=$AnalyticFifoDepth base=${BaseTileW}x${BaseTileH} set=$SectorSetNum way=$SectorWayNum merge_x=$MergeMaxX merge_min_en=$EnableMergeMin merge_min_x=$MergeMinX fifo_age=$FifoAgeLimit throttle_en=$EnablePrefetchThrottle throttle_cycles=$PrefetchThrottleCycles row_bucket=$EnableRowBucketMerge row_bucket_min=$RowBucketMinX runtime_lead=$RuntimeLeadPixels runtime_merge_max=$RuntimeMergeMaxX runtime_merge_min=$RuntimeMergeMinX runtime_fifo=$RuntimeFifoDepth runtime_fifo_age=$RuntimeFifoAgeLimit runtime_throttle=$RuntimePrefetchThrottleCycles runtime_policy=$RuntimeSchedulerPolicy rd_burst=$RdBurstMaxLen rd_ob=$RdMaxOutstandingBursts rd_beats=$RdMaxOutstandingBeats rd_fifo=$RdFifoDepthWords wr_burst=$WrBurstMaxLen wr_fifo=$WrFifoDepthPixels profile=$profileMode compile_mode=$compileMode"
Set-Content -Path $summaryPath -Value @(
    "CACHE_PERF_RUN $safeRunName",
    $paramLine,
    "compile_timeout=$CompileTimeoutSec elab_timeout=$ElabTimeoutSec sim_timeout=$SimTimeoutSec",
    "out_dir=$outDir"
)

try {
    Invoke-ToolWithTimeout -FilePath "xvlog" -Arguments $compileArgs -TimeoutSec $CompileTimeoutSec -LogPath $compileLog
    if ($CompileOnly -or $TbOnlyCompile) {
        Add-Content -Path $summaryPath -Value "status=compile_only_pass"
        Write-Host "Compile log: $compileLog"
        exit 0
    }

    $elabArgs = @("xil_defaultlib.$Top", "-L", "xpm", "-s", $snapshot, "--timescale", "1ns/1ps", "--log", $elabLog)
    Invoke-ToolWithTimeout -FilePath "xelab" -Arguments $elabArgs -TimeoutSec $ElabTimeoutSec -LogPath $elabLog
    if ($ElabOnly) {
        Add-Content -Path $summaryPath -Value "status=elab_only_pass"
        Write-Host "Elab log: $elabLog"
        exit 0
    }

    $simArgs = @($snapshot, "--log", $simLog, "--onfinish", "quit", "--runall")
    Invoke-ToolWithTimeout -FilePath "xsim" -Arguments $simArgs -TimeoutSec $SimTimeoutSec -LogPath $simLog

    $failed = Select-String -Path $simLog -Pattern '^\s*Fatal:', '^\s*ERROR:', '^\s*\$fatal' -Quiet
    $interesting = Select-String -Path $simLog -Pattern 'PERF_SINGLE|PERF_SINGLE_TIMEOUT|Fatal:|ERROR:' -ErrorAction SilentlyContinue
    if ($interesting) {
        Add-Content -Path $summaryPath -Value ""
        Add-Content -Path $summaryPath -Value "Key lines:"
        foreach ($line in $interesting) {
            Add-Content -Path $summaryPath -Value $line.Line
        }
    }

    if ($failed) {
        Add-Content -Path $summaryPath -Value "status=sim_failed"
        throw "Simulation failed. See log: $simLog"
    }

    Add-Content -Path $summaryPath -Value "status=pass"
    Write-Host "Perf run summary: $summaryPath"
    Write-Host "Sim log: $simLog"
} catch {
    Add-Content -Path $summaryPath -Value "status=failed"
    Add-Content -Path $summaryPath -Value ("error=" + $_.Exception.Message)
    throw
}
