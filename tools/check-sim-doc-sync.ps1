[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# 检查 `rtl/sim` 下的 testbench 与同名 Markdown 说明文档是否保持同步。
$repoRoot = Split-Path -Parent $PSScriptRoot
$simDir = Join-Path $repoRoot "rtl\sim"

$tbFiles = Get-ChildItem $simDir -Filter "tb_*.sv" | Sort-Object Name
$mdFiles = Get-ChildItem $simDir -Filter "tb_*.md" | Sort-Object Name
$errors = New-Object System.Collections.Generic.List[string]

foreach ($tb in $tbFiles) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($tb.Name)
    $mdPath = Join-Path $simDir ($base + ".md")

    if (-not (Test-Path $mdPath)) {
        $errors.Add("Missing markdown for $($tb.Name)")
        continue
    }

    # 要求 testbench 文件头部带有同步提醒，降低“代码变了但文档没改”的概率。
    $tbHead = Get-Content $tb.FullName -Encoding UTF8 | Select-Object -First 5
    $expectedSyncLine = "Keep $base.md in sync"
    if (-not ($tbHead -match [regex]::Escape($expectedSyncLine))) {
        $errors.Add("$($tb.Name) is missing sync reminder comment: '$expectedSyncLine'")
    }

    # 对说明文档做最小结构校验，确保关键信息齐全。
    $mdText = Get-Content $mdPath -Raw -Encoding UTF8
    foreach ($required in @("DUT:", "Testbench:", "## ", "结果")) {
        if ($mdText -notmatch [regex]::Escape($required)) {
            $errors.Add("$([System.IO.Path]::GetFileName($mdPath)) is missing required marker '$required'")
        }
    }
}

foreach ($md in $mdFiles) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($md.Name)
    $tbPath = Join-Path $simDir ($base + ".sv")
    if (-not (Test-Path $tbPath)) {
        $errors.Add("Markdown has no matching testbench: $($md.Name)")
    }
}

if ($errors.Count -gt 0) {
    Write-Host "Simulation doc sync check failed:`n"
    foreach ($err in $errors) {
        Write-Host " - $err"
    }
    exit 1
}

Write-Host "Simulation doc sync check passed."
