[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target = "all",

    [switch]$Wave,
    [switch]$GtkWave,
    [switch]$Clean,
    [int]$CompileTimeoutSec = 60,
    [int]$ElabTimeoutSec = 60,
    [int]$SimTimeoutSec = 20,
    [switch]$CompileOnly,
    [switch]$ElabOnly
)

$ErrorActionPreference = "Stop"

# 统一封装模块级仿真流程：
# 1. 选择目标模块与源码集合；
# 2. 依次执行 xvlog -> xelab -> xsim；
# 3. 在 sim_out/<target>/ 输出日志、波形和结果摘要。
$repoRoot = Split-Path -Parent $PSScriptRoot
$outRoot = Join-Path $repoRoot "sim_out"
$waveTcl = Join-Path $PSScriptRoot "xsim_runall_log_waves.tcl"

function Convert-ToXsimPath {
    param([string]$Path)
    # xsim 对正斜杠路径更友好，这里统一转换。
    return ($Path -replace "\\", "/")
}

# 每个目标都显式列出顶层 testbench、snapshot 名和依赖源码。
$targets = @{
    "scale_core_nearest" = @{
        Top = "tb_scale_core_nearest"
        Snapshot = "tb_scale_core_nearest_auto"
        Sources = @(
            "rtl/core/scale_core_nearest.sv",
            "rtl/sim/tb_scale_core_nearest.sv"
        )
    }
    "pixel_unpacker" = @{
        Top = "tb_pixel_unpacker"
        Snapshot = "tb_pixel_unpacker_auto"
        Sources = @(
            "rtl/core/pixel_unpacker.sv",
            "rtl/sim/tb_pixel_unpacker.sv"
        )
    }
    "task_cdc" = @{
        Top = "tb_task_cdc"
        Snapshot = "tb_task_cdc_auto"
        Sources = @(
            "rtl/buffer/async_word_fifo.sv",
            "rtl/axi/task_cdc.sv",
            "rtl/sim/tb_task_cdc.sv"
        )
    }
    "result_cdc" = @{
        Top = "tb_result_cdc"
        Snapshot = "tb_result_cdc_auto"
        Sources = @(
            "rtl/buffer/async_word_fifo.sv",
            "rtl/axi/result_cdc.sv",
            "rtl/sim/tb_result_cdc.sv"
        )
    }
    "cache_stats_cdc" = @{
        Top = "tb_cache_stats_cdc_back_to_back"
        Snapshot = "tb_cache_stats_cdc_back_to_back_auto"
        Sources = @(
            "rtl/buffer/async_word_fifo.sv",
            "rtl/axi/cache_stats_cdc.sv",
            "rtl/sim/tb_cache_stats_cdc_back_to_back.sv"
        )
    }
    "async_word_fifo" = @{
        Top = "tb_async_word_fifo_xpm"
        Snapshot = "tb_async_word_fifo_xpm_auto"
        Sources = @(
            "rtl/buffer/async_word_fifo.sv",
            "rtl/sim/tb_async_word_fifo_xpm.sv"
        )
    }
    "src_line_buffer" = @{
        Top = "tb_src_line_buffer"
        Snapshot = "tb_src_line_buffer_auto"
        Sources = @(
            "rtl/buffer/src_line_buffer.sv",
            "rtl/sim/tb_src_line_buffer.sv"
        )
    }
    "src_tile_cache" = @{
        Top = "tb_src_tile_cache"
        Snapshot = "tb_src_tile_cache_auto"
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/buffer/src_tile_cache.sv",
            "rtl/sim/tb_src_tile_cache.sv"
        )
    }
    "rotate_geom_init_unit" = @{
        Top = "tb_rotate_geom_init_unit"
        Snapshot = "tb_rotate_geom_init_unit_auto"
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/sim/tb_rotate_geom_init_unit.sv"
        )
    }
    "src_tile_cache_prefetch" = @{
        Top = "tb_src_tile_cache_prefetch"
        Snapshot = "tb_src_tile_cache_prefetch_auto"
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/buffer/src_tile_cache.sv",
            "rtl/sim/tb_src_tile_cache_prefetch.sv"
        )
    }
    "src_tile_cache_analytic_trace" = @{
        Top = "tb_src_tile_cache_analytic_trace"
        Snapshot = "tb_src_tile_cache_analytic_trace_auto"
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/buffer/src_tile_cache.sv",
            "rtl/sim/tb_src_tile_cache_analytic_trace.sv"
        )
    }
    "src_tile_cache_merge_reservation" = @{
        Top = "tb_src_tile_cache_merge_reservation"
        Snapshot = "tb_src_tile_cache_merge_reservation_auto"
        Defines = @(
            "SRC_TILE_CACHE_SECTOR_SET_NUM=2",
            "SRC_TILE_CACHE_SECTOR_WAY_NUM=4",
            "SRC_TILE_CACHE_MERGE_MAX_X=8",
            "SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH=16",
            "SRC_TILE_CACHE_ANALYTIC_LEAD_PIXELS=64"
        )
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/buffer/src_tile_cache.sv",
            "rtl/sim/tb_src_tile_cache_merge_reservation.sv"
        )
    }
    "src_tile_cache_prefetch_merge_min" = @{
        Top = "tb_src_tile_cache_prefetch"
        Snapshot = "tb_src_tile_cache_prefetch_merge_min_auto"
        Defines = @(
            "SRC_TILE_CACHE_ENABLE_MERGE_MIN=1",
            "SRC_TILE_CACHE_MERGE_MIN_X=4",
            "SRC_TILE_CACHE_FIFO_AGE_LIMIT=20",
            "SRC_TILE_CACHE_MERGE_MAX_X=8",
            "SRC_TILE_CACHE_ANALYTIC_FIFO_DEPTH=32"
        )
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/buffer/src_tile_cache.sv",
            "rtl/sim/tb_src_tile_cache_prefetch.sv"
        )
    }
    "src_tile_cache_prefetch_throttle" = @{
        Top = "tb_src_tile_cache_prefetch"
        Snapshot = "tb_src_tile_cache_prefetch_throttle_auto"
        Defines = @(
            "SRC_TILE_CACHE_ENABLE_PREFETCH_THROTTLE=1",
            "SRC_TILE_CACHE_PREFETCH_THROTTLE_CYCLES=32"
        )
        Sources = @(
            "rtl/core/rotate_geom_init_unit.sv",
            "rtl/buffer/src_tile_cache.sv",
            "rtl/sim/tb_src_tile_cache_prefetch.sv"
        )
    }
    "scaler_ctrl" = @{
        Top = "tb_scaler_ctrl"
        Snapshot = "tb_scaler_ctrl_auto"
        Sources = @(
            "rtl/ctrl/scaler_ctrl.sv",
            "rtl/sim/tb_scaler_ctrl.sv"
        )
    }
    "rotate_core_bilinear_trace" = @{
        Top = "tb_rotate_core_bilinear_trace"
        Snapshot = "tb_rotate_core_bilinear_trace_auto"
        Sources = @(
            "rtl/core/row_advance_unit.sv",
            "rtl/core/rotate_core_bilinear.sv",
            "rtl/sim/tb_rotate_core_bilinear_trace.sv"
        )
    }
    "ddr_read_engine" = @{
        Top = "tb_ddr_read_engine"
        Snapshot = "tb_ddr_read_engine_auto"
        Sources = @(
            "axi/rtl/taxi_axi_if.sv",
            "rtl/axi/ddr_axi_pkg.sv",
            "rtl/axi/task_cdc_2d.sv",
            "rtl/axi/result_cdc.sv",
    "rtl/axi/axi_burst_reader.sv",
    "rtl/buffer/async_word_fifo.sv",
    "rtl/core/pixel_packer.sv",
    "rtl/core/pixel_unpacker.sv",
            "rtl/axi/ddr_read_engine.sv",
            "rtl/sim/tb_ddr_read_engine.sv"
        )
    }
    "ddr_write_engine" = @{
        Top = "tb_ddr_write_engine"
        Snapshot = "tb_ddr_write_engine_auto"
        Sources = @(
            "axi/rtl/taxi_axi_if.sv",
            "rtl/axi/ddr_axi_pkg.sv",
            "rtl/axi/reset_sync.sv",
            "rtl/axi/task_cdc.sv",
            "rtl/axi/task_cdc_2d.sv",
            "rtl/axi/result_cdc.sv",
            "rtl/buffer/async_word_fifo.sv",
            "rtl/core/pixel_packer.sv",
            "rtl/axi/axi_burst_writer.sv",
            "rtl/axi/ddr_write_engine.sv",
            "rtl/sim/tb_ddr_write_engine.sv"
        )
    }
    "image_geo_top" = @{
        Top = "tb_image_geo_top"
        Snapshot = "tb_image_geo_top_auto"
        Sources = @(
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
            "rtl/sim/tb_image_geo_top.sv"
        )
    }
    "image_geo_top_prefetch_stress" = @{
        Top = "tb_image_geo_top_prefetch_stress"
        Snapshot = "tb_image_geo_top_prefetch_stress_auto"
        Sources = @(
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
            "rtl/sim/tb_image_geo_top_prefetch_stress.sv"
        )
    }
    "image_geo_top_perf_sweep" = @{
        Top = "tb_image_geo_top_perf_sweep"
        Snapshot = "tb_image_geo_top_perf_sweep_auto"
        Sources = @(
            "axi/rtl/taxi_axi_if.sv",
            "rtl/axi/ddr_axi_pkg.sv",
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
            "rtl/sim/tb_image_geo_top_perf_sweep.sv"
        )
    }
}

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

function Invoke-Step {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSec = 60,
        [string]$LogPath = ""
    )

    # 统一执行外部工具，失败/超时时立刻抛错终止流程。
    Write-Host ">> $FilePath $($Arguments -join ' ')"
    $resolvedPath = (Get-Command $FilePath -ErrorAction Stop).Source
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedPath
    $psi.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
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
        throw "Command failed: $FilePath $($Arguments -join ' ')"
    }
}

function Stop-XsimProcesses {
    # 超时时顺手清理残留的 xsim/xelab/xvlog 进程，避免影响下一次运行。
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "xsim*" -or $_.ProcessName -like "xelab*" -or $_.ProcessName -like "xvlog*"
    }
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-XsimWithTimeout {
    param(
        [string[]]$Arguments,
        [string]$LogPath,
        [int]$TimeoutSec
    )

    # xsim 单独做超时控制，防止 GUI/仿真卡住后一直不退出。
    Write-Host ">> xsim $($Arguments -join ' ')"
    $resolvedPath = (Get-Command "xsim" -ErrorAction Stop).Source
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedPath
    $psi.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    Start-Sleep -Seconds 1
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
        throw "Simulation timed out after ${TimeoutSec}s. See log: $LogPath"
    }

    if ($proc.ExitCode -ne 0) {
        throw "xsim exited with code $($proc.ExitCode). See log: $LogPath"
    }
}

function Resolve-TargetNames {
    param([string]$Name)

    if ($Name -eq "all") {
        # all 会展开成脚本当前维护的全部目标。
        return @("scale_core_nearest", "pixel_unpacker", "task_cdc", "result_cdc", "cache_stats_cdc", "async_word_fifo", "src_line_buffer", "rotate_geom_init_unit", "rotate_core_bilinear_trace", "src_tile_cache", "src_tile_cache_prefetch", "src_tile_cache_analytic_trace", "src_tile_cache_merge_reservation", "src_tile_cache_prefetch_merge_min", "src_tile_cache_prefetch_throttle", "scaler_ctrl", "ddr_read_engine", "ddr_write_engine", "image_geo_top", "image_geo_top_prefetch_stress", "image_geo_top_perf_sweep")
    }

    if (-not $targets.ContainsKey($Name)) {
        $valid = ($targets.Keys | Sort-Object) -join ", "
        throw "Unknown target '$Name'. Valid values: all, $valid"
    }

    return @($Name)
}

function Run-OneTarget {
    param(
        [string]$Name,
        [hashtable]$Cfg
    )

    # 每个目标使用独立输出目录，便于保留最近一次日志和波形。
    $targetOutDir = Join-Path $outRoot $Name
    if ($Clean -and (Test-Path $targetOutDir)) {
        Remove-Item -LiteralPath $targetOutDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $targetOutDir -Force | Out-Null

    $compileLog = Join-Path $targetOutDir "xvlog.log"
    $elabLog = Join-Path $targetOutDir "xelab.log"
    $simLog = Join-Path $targetOutDir "xsim.log"
    $wdbPath = Join-Path $targetOutDir "$($Cfg.Top).wdb"
    $vcdPath = Join-Path $targetOutDir "$($Cfg.Top).vcd"

    # xvlog 统一按 SystemVerilog 模式编译。Vivado 2019.2 对 `-d NAME=VALUE`
    # 兼容性不好，带参数 target 用临时 define 文件更稳。
    $sourceArgs = @("-sv")
    if ($Cfg.ContainsKey("Defines")) {
        $defineFile = Join-Path $targetOutDir "module_defines.sv"
        $defineLines = @()
        foreach ($define in $Cfg.Defines) {
            $parts = $define -split "=", 2
            if ($parts.Count -eq 2) {
                $defineLines += "``define $($parts[0]) $($parts[1])"
            } else {
                $defineLines += "``define $define"
            }
        }
        Set-Content -Path $defineFile -Value $defineLines -Encoding ASCII
        $sourceArgs += $defineFile
    }
    foreach ($src in $Cfg.Sources) {
        $sourceArgs += (Join-Path $repoRoot $src)
    }
    $sourceArgs += @("--log", $compileLog)
    Invoke-Step -FilePath "xvlog" -Arguments $sourceArgs -WorkingDirectory $repoRoot -TimeoutSec $CompileTimeoutSec -LogPath $compileLog
    if ($CompileOnly) {
        return [pscustomobject]@{
            Target = $Name
            Top = $Cfg.Top
            CompileLog = $compileLog
            ElabLog = ""
            SimLog = ""
            Wdb = ""
            Vcd = ""
        }
    }

    # 固定 snapshot 名，便于后续 xsim 调用。
    $elabArgs = @($Cfg.Top, "-s", $Cfg.Snapshot, "--timescale", "1ns/1ps", "--log", $elabLog)
    if ($Wave -or $GtkWave) {
        $elabArgs += @("--debug", "wave")
    }
    Invoke-Step -FilePath "xelab" -Arguments $elabArgs -WorkingDirectory $repoRoot -TimeoutSec $ElabTimeoutSec -LogPath $elabLog
    if ($ElabOnly) {
        return [pscustomobject]@{
            Target = $Name
            Top = $Cfg.Top
            CompileLog = $compileLog
            ElabLog = $elabLog
            SimLog = ""
            Wdb = ""
            Vcd = ""
        }
    }

    # 需要波形时输出 WDB；若指定 GtkWave，再额外导出 VCD。
    $simArgs = @($Cfg.Snapshot, "--log", $simLog, "--onfinish", "quit")
    if ($Wave -or $GtkWave) {
        if ($GtkWave) {
            $env:XSIM_VCD_FILE = Convert-ToXsimPath $vcdPath
        } else {
            Remove-Item Env:XSIM_VCD_FILE -ErrorAction SilentlyContinue
        }
        $simArgs += @("--wdb", (Convert-ToXsimPath $wdbPath), "--tclbatch", (Convert-ToXsimPath $waveTcl))
    } else {
        Remove-Item Env:XSIM_VCD_FILE -ErrorAction SilentlyContinue
        $simArgs += @("--runall")
    }
    Invoke-XsimWithTimeout -Arguments $simArgs -LogPath $simLog -TimeoutSec $SimTimeoutSec
    Remove-Item Env:XSIM_VCD_FILE -ErrorAction SilentlyContinue

    # 用关键字扫描做最后一道保守失败判定。
    $simFailed = Select-String -Path $simLog -Pattern '^\s*Fatal:', '^\s*ERROR:', '^\s*\$fatal' -Quiet
    if ($simFailed) {
        throw "Simulation failed for target '$Name'. See log: $simLog"
    }

    [pscustomobject]@{
        Target = $Name
        Top = $Cfg.Top
        CompileLog = $compileLog
        ElabLog = $elabLog
        SimLog = $simLog
        Wdb = $(if ($Wave -or $GtkWave) { $wdbPath } else { "" })
        Vcd = $(if ($GtkWave) { $vcdPath } else { "" })
    }
}

New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

$results = @()
foreach ($name in (Resolve-TargetNames -Name $Target)) {
    Write-Host "== Running target: $name =="
    $results += Run-OneTarget -Name $name -Cfg $targets[$name]
}

Write-Host ""
Write-Host "Simulation summary:"
foreach ($item in $results) {
    if ($item.SimLog) {
        Write-Host "  [$($item.Target)] sim log: $($item.SimLog)"
    } elseif ($item.ElabLog) {
        Write-Host "  [$($item.Target)] elab log: $($item.ElabLog)"
    } else {
        Write-Host "  [$($item.Target)] compile log: $($item.CompileLog)"
    }
    if ($item.Wdb) {
        Write-Host "  [$($item.Target)] wave db: $($item.Wdb)"
    }
    if ($item.Vcd) {
        Write-Host "  [$($item.Target)] vcd: $($item.Vcd)"
    }
}
