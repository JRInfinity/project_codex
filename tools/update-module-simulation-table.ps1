[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# 把 docs/module_simulation.md 中的模块状态表按当前工作区真实信息重新生成。
function U {
    param([string]$Text)
    return [regex]::Unescape($Text)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$docPath = Join-Path $repoRoot "docs/module_simulation.md"
$simRoot = Join-Path $repoRoot "rtl/sim"
$simOutRoot = Join-Path $repoRoot "sim_out"

$tableBegin = "<!-- STATUS_TABLE_BEGIN -->"
$tableEnd = "<!-- STATUS_TABLE_END -->"

$labels = @{
    Module = U('\u6a21\u5757')
    ModuleDone = U('\u6a21\u5757\u5b8c\u6210')
    SimFiles = U('\u4eff\u771f\u6587\u4ef6')
    SimulatedVersion = U('\u5df2\u4eff\u771f')
    SimResult = U('\u4eff\u771f\u7ed3\u679c')
    Note = U('\u5907\u6ce8')
    Explain = U('\u8bf4\u660e\uff1a')
    Yes = U('\u662f')
    No = U('\u5426')
    None = U('\u65e0')
    NotRun = U('\u672a\u9a8c\u8bc1')
    Unknown = U('\u672a\u77e5')
    Pass = U('\u901a\u8fc7')
    Fail = U('\u5931\u8d25')
    VersionUnknown = U('\u7248\u672c\u672a\u77e5')
    MissingMd = U('\u7f3a\u5c11 .md')
    MissingSv = U('\u7f3a\u5c11 .sv')
}

# 每条规则描述一个 RTL 模块与其 testbench/说明文档/仿真目标的对应关系。
$moduleRules = @(
    @{
        Module = "image_geo_top"
        RtlPath = "rtl/image_geo_top.sv"
        SimTarget = "image_geo_top"
        TbFile = "tb_image_geo_top.sv"
        MdFile = "tb_image_geo_top.md"
        Note = U('\u9876\u5c42 Stage A \u8054\u8c03\u4eff\u771f')
    }
    @{
        Module = "axi_burst_reader"
        RtlPath = "rtl/axi/axi_burst_reader.sv"
        SimTarget = $null
        TbFile = $null
        MdFile = $null
        Note = U('\u8fd8\u6ca1\u6709\u72ec\u7acb\u6a21\u5757\u7ea7 testbench')
    }
    @{
        Module = "ddr_read_engine"
        RtlPath = "rtl/axi/ddr_read_engine.sv"
        SimTarget = "ddr_read_engine"
        TbFile = "tb_ddr_read_engine.sv"
        MdFile = "tb_ddr_read_engine.md"
        Note = U('\u5df2\u5b8c\u6210\u6a21\u5757\u7ea7\u8054\u8c03')
    }
    @{
        Module = "task_cdc"
        RtlPath = "rtl/axi/task_cdc.sv"
        SimTarget = "task_cdc"
        TbFile = "tb_task_cdc.sv"
        MdFile = "tb_task_cdc.md"
        Note = U('CDC task \u901a\u9053\u5df2\u9a8c\u8bc1')
    }
    @{
        Module = "result_cdc"
        RtlPath = "rtl/axi/result_cdc.sv"
        SimTarget = "result_cdc"
        TbFile = "tb_result_cdc.sv"
        MdFile = "tb_result_cdc.md"
        Note = U('CDC result \u901a\u9053\u5df2\u9a8c\u8bc1')
    }
    @{
        Module = "async_word_fifo"
        RtlPath = "rtl/buffer/async_word_fifo.sv"
        SimTarget = "async_word_fifo"
        TbFile = "tb_async_word_fifo_xpm.sv"
        MdFile = "tb_async_word_fifo_xpm.md"
        Note = U('\u4eff\u771f fallback \u5df2\u4fee\u590d\u5e76\u9a8c\u8bc1')
    }
    @{
        Module = "src_line_buffer"
        RtlPath = "rtl/buffer/src_line_buffer.sv"
        SimTarget = "src_line_buffer"
        TbFile = "tb_src_line_buffer.sv"
        MdFile = "tb_src_line_buffer.md"
        Note = U('\u53cc\u8bfb\u53e3\u548c\u9519\u8bef\u8def\u5f84\u5df2\u9a8c\u8bc1')
    }
    @{
        Module = "pixel_unpacker"
        RtlPath = "rtl/core/pixel_unpacker.sv"
        SimTarget = "pixel_unpacker"
        TbFile = "tb_pixel_unpacker.sv"
        MdFile = "tb_pixel_unpacker.md"
        Note = U('\u62c6\u5305\u4e0e\u9519\u8bef\u5904\u7406\u5df2\u9a8c\u8bc1')
    }
    @{
        Module = "scale_core_nearest"
        RtlPath = "rtl/core/scale_core_nearest.sv"
        SimTarget = "scale_core_nearest"
        TbFile = "tb_scale_core_nearest.sv"
        MdFile = "tb_scale_core_nearest.md"
        Note = U('\u6700\u8fd1\u90bb\u6838\u5fc3\u5df2\u9a8c\u8bc1')
    }
)

function Get-VersionFromMarkdown {
    param([string]$Path)

    # 说明文档里约定使用 `- Version:` 记录最近一次维护版本号。
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $match = Select-String -Path $Path -Pattern '^\s*-\s*Version:\s*`?([^`]+)`?\s*$' -Encoding UTF8
    if ($match) {
        return $match.Matches[0].Groups[1].Value.Trim()
    }

    return $null
}

function Get-SimResultFromLog {
    param([string]$Path)

    # 只根据真实 xsim 日志判断结果，不做额外推测。
    if (-not (Test-Path -LiteralPath $Path)) {
        return $labels.NotRun
    }

    $content = Get-Content -Path $Path -Encoding UTF8
    $joined = $content -join "`n"

    if ($joined -match '(?im)^\s*(Fatal:|ERROR:|\$fatal)') {
        return $labels.Fail
    }

    if ($joined -match '(?im)completed' -and $joined -match '(?im)exit 0') {
        return $labels.Pass
    }

    return $labels.Unknown
}

# 逐条规则生成 Markdown 表格行。
$rows = foreach ($rule in $moduleRules) {
    $rtlPath = Join-Path $repoRoot $rule.RtlPath
    $moduleDone = if (Test-Path -LiteralPath $rtlPath) { $labels.Yes } else { $labels.No }

    $tbLabel = $labels.None
    $simVersion = $labels.None
    $simResult = $labels.NotRun

    if ($rule.TbFile -and $rule.MdFile) {
        $tbPath = Join-Path $simRoot $rule.TbFile
        $mdPath = Join-Path $simRoot $rule.MdFile
        $tbExists = Test-Path -LiteralPath $tbPath
        $mdExists = Test-Path -LiteralPath $mdPath
        $version = Get-VersionFromMarkdown -Path $mdPath

        if ($tbExists -and $mdExists) {
            $tbLabel = if ($version) {
                "$($rule.TbFile) ($version)"
            } else {
                "$($rule.TbFile) ($($labels.VersionUnknown))"
            }
        } elseif ($tbExists) {
            $tbLabel = "$($rule.TbFile) ($($labels.MissingMd))"
        } elseif ($mdExists) {
            $tbLabel = "$($rule.MdFile) ($($labels.MissingSv))"
        }

        if ($rule.SimTarget) {
            $logPath = Join-Path $simOutRoot (Join-Path $rule.SimTarget "xsim.log")
            if ($tbExists -and $mdExists -and (Test-Path -LiteralPath $logPath)) {
                $simResult = Get-SimResultFromLog -Path $logPath
                $simVersion = if ($version) { $version } else { $labels.VersionUnknown }
            }
        }
    }

    "| ``$($rule.Module)`` | $moduleDone | ``$tbLabel`` | ``$simVersion`` | $simResult | $($rule.Note) |"
}

$line1 = '- `'+$labels.ModuleDone+'` '+(U('\u53ea\u8868\u793a\u5bf9\u5e94 RTL \u6587\u4ef6\u786e\u5b9e\u5b58\u5728\u4e8e `rtl/`\u3002'))
$line2 = '- `'+$labels.SimFiles+'` '+(U('\u53ea\u6709\u5728 `tb_*.sv` \u548c\u5bf9\u5e94 `.md` \u90fd\u771f\u5b9e\u5b58\u5728\u65f6\u624d\u8bb0\u4e3a\u6709\u6548\u3002'))
$line3 = '- `'+$labels.SimulatedVersion+'` '+(U('\u53ea\u6709\u5728\u5bf9\u5e94 `sim_out/<target>/xsim.log` \u771f\u5b9e\u5b58\u5728\u65f6\u624d\u586b\u5199\u7248\u672c\u3002'))
$line4 = '- `'+$labels.SimResult+'` '+(U('\u53ea\u6839\u636e\u5f53\u524d\u5de5\u4f5c\u533a\u65e5\u5fd7\u4e2d\u7684\u771f\u5b9e\u7ed3\u679c\u586b\u5199\u3002'))
$line5 = '- '+(U('\u7f3a\u5c11\u8bc1\u636e\u65f6\uff0c\u4fdd\u6301\u4fdd\u5b88\u663e\u793a\u4e3a '))+'`'+$labels.None+'`'+(U('\u3001'))+'`'+$labels.NotRun+'` '+(U('\u6216'))+' `'+$labels.Unknown+'`'+(U('\u3002'))
$header = '| '+$labels.Module+' | '+$labels.ModuleDone+' | '+$labels.SimFiles+' | '+$labels.SimulatedVersion+' | '+$labels.SimResult+' | '+$labels.Note+' |'

$newTable = @(
    $tableBegin
    ""
    $labels.Explain
    ""
    $line1
    $line2
    $line3
    $line4
    $line5
    $header
    '| --- | --- | --- | --- | --- | --- |'
) + $rows + @(
    $tableEnd
)

# 借助锚点注释只替换表格区域，避免误改文档其它内容。
$docText = Get-Content -Path $docPath -Raw -Encoding UTF8
$pattern = "(?s)$([regex]::Escape($tableBegin)).*?$([regex]::Escape($tableEnd))"
$replacement = $newTable -join "`r`n"

if ($docText -notmatch $pattern) {
    throw "Status table markers not found in $docPath"
}

$updated = [regex]::Replace(
    $docText,
    $pattern,
    [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement },
    1
)

[System.IO.File]::WriteAllText($docPath, $updated, [System.Text.UTF8Encoding]::new($false))

Write-Host ("Status table refreshed: " + $docPath)
