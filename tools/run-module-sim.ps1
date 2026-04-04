[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target = "all",

    [switch]$Wave,
    [switch]$GtkWave,
    [switch]$Clean,
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
            "rtl/axi/task_cdc.sv",
            "rtl/sim/tb_task_cdc.sv"
        )
    }
    "result_cdc" = @{
        Top = "tb_result_cdc"
        Snapshot = "tb_result_cdc_auto"
        Sources = @(
            "rtl/axi/result_cdc.sv",
            "rtl/sim/tb_result_cdc.sv"
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
    "ddr_read_engine" = @{
        Top = "tb_ddr_read_engine"
        Snapshot = "tb_ddr_read_engine_auto"
        Sources = @(
            "axi/rtl/taxi_axi_if.sv",
            "rtl/axi/ddr_axi_pkg.sv",
            "rtl/axi/task_cdc.sv",
            "rtl/axi/result_cdc.sv",
            "rtl/axi/axi_burst_reader.sv",
            "rtl/buffer/async_word_fifo.sv",
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
            "rtl/axi/task_cdc.sv",
            "rtl/axi/result_cdc.sv",
            "rtl/axi/axi_burst_reader.sv",
            "rtl/buffer/async_word_fifo.sv",
            "rtl/core/pixel_unpacker.sv",
            "rtl/axi/ddr_read_engine.sv",
            "rtl/axi/ddr_write_engine.sv",
            "rtl/buffer/src_line_buffer.sv",
            "rtl/buffer/row_out_buffer.sv",
            "rtl/core/scale_core_nearest.sv",
            "rtl/ctrl/scaler_ctrl.sv",
            "rtl/image_geo_top.sv",
            "rtl/sim/tb_image_geo_top.sv"
        )
    }
}

function Invoke-Step {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    # 统一执行外部工具，失败时立刻抛错终止流程。
    Write-Host ">> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
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
    $proc = Start-Process xsim -ArgumentList $Arguments -PassThru -WorkingDirectory $repoRoot
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
        return @("scale_core_nearest", "pixel_unpacker", "task_cdc", "result_cdc", "async_word_fifo", "src_line_buffer", "ddr_read_engine", "ddr_write_engine", "image_geo_top")
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

    # xvlog 统一按 SystemVerilog 模式编译。
    $sourceArgs = @("-sv")
    foreach ($src in $Cfg.Sources) {
        $sourceArgs += (Join-Path $repoRoot $src)
    }
    $sourceArgs += @("--log", $compileLog)
    Invoke-Step -FilePath "xvlog" -Arguments $sourceArgs -WorkingDirectory $repoRoot
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
    Invoke-Step -FilePath "xelab" -Arguments $elabArgs -WorkingDirectory $repoRoot
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
