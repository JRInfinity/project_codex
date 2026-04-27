[CmdletBinding()]
param(
    [switch]$Staged,
    [string]$Base = "HEAD"
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param([string[]]$GitArgs)
    $output = & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed"
    }
    return $output
}

function Normalize-Path {
    param([string]$Path)
    return ($Path -replace "\\", "/")
}

function Get-ChangedPaths {
    param([switch]$OnlyStaged, [string]$DiffBase)

    $paths = New-Object System.Collections.Generic.HashSet[string]

    if ($OnlyStaged) {
        foreach ($p in (Invoke-Git @("diff", "--cached", "--name-only", "--diff-filter=ACMRT"))) {
            if ($p) { [void]$paths.Add((Normalize-Path $p)) }
        }
    }
    else {
        foreach ($p in (Invoke-Git @("diff", "--name-only", "--diff-filter=ACMRT", $DiffBase))) {
            if ($p) { [void]$paths.Add((Normalize-Path $p)) }
        }
        foreach ($p in (Invoke-Git @("diff", "--cached", "--name-only", "--diff-filter=ACMRT"))) {
            if ($p) { [void]$paths.Add((Normalize-Path $p)) }
        }
        foreach ($p in (Invoke-Git @("ls-files", "--others", "--exclude-standard"))) {
            if ($p) { [void]$paths.Add((Normalize-Path $p)) }
        }
    }

    return $paths
}

function Get-SvObjects {
    param([string]$RepoRoot, [string]$RelPath)

    $fullPath = Join-Path $RepoRoot ($RelPath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path $fullPath)) {
        return @()
    }

    $text = Get-Content -Path $fullPath -Raw -Encoding UTF8
    $text = [regex]::Replace($text, "(?s)/\*.*?\*/", " ")
    $text = [regex]::Replace($text, "//.*", " ")

    $objects = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($text, "(?m)^\s*(?:module|package)\s+([A-Za-z_][A-Za-z0-9_]*)")) {
        $name = $m.Groups[1].Value
        if ($name) { $objects.Add($name) }
    }

    return $objects.ToArray()
}

function Get-ExpectedDocs {
    param([string]$RelPath, [string[]]$Objects)

    $docs = New-Object System.Collections.Generic.HashSet[string]

    foreach ($name in $Objects) {
        if ($name -like "taxi_*") {
            [void]$docs.Add("docs/module_index.md")
            [void]$docs.Add("docs/interfaces/axi_ddr.md")
            continue
        }

        [void]$docs.Add("docs/modules/$name.md")

        if ($RelPath -like "rtl/sim/*") {
            [void]$docs.Add("docs/verification_status.md")
        }
    }

    if ($RelPath -like "rtl/top/*") {
        [void]$docs.Add("docs/README.md")
        [void]$docs.Add("docs/image_pipeline.md")
    }
    elseif ($RelPath -like "rtl/axi/*") {
        [void]$docs.Add("docs/interfaces/axi_ddr.md")
        if ($RelPath -match "cdc|reset_sync|task_cdc|result_cdc|frame_config_cdc|cache_stats_cdc") {
            [void]$docs.Add("docs/interfaces/cdc_reset.md")
        }
    }
    elseif ($RelPath -like "rtl/buffer/src_tile_cache.sv") {
        [void]$docs.Add("docs/cache_and_prefetch.md")
    }
    elseif ($RelPath -like "rtl/core/rotate_core_bilinear.sv") {
        [void]$docs.Add("docs/image_pipeline.md")
    }

    return @($docs)
}

$repoRoot = (Invoke-Git @("rev-parse", "--show-toplevel") | Select-Object -First 1)
Set-Location $repoRoot

$changed = Get-ChangedPaths -OnlyStaged:$Staged -DiffBase $Base
$changedDocs = New-Object System.Collections.Generic.HashSet[string]
foreach ($p in $changed) {
    if ($p -like "docs/*") { [void]$changedDocs.Add($p) }
}

$rtlChanges = @(
    $changed |
        Where-Object {
            ($_ -like "rtl/*.sv" -or $_ -like "rtl/*.svh" -or $_ -like "rtl/*/*.sv" -or $_ -like "rtl/*/*.svh" -or
             $_ -like "axi/rtl/*.sv" -or $_ -like "axi/rtl/*.svh") -and
            ($_ -notlike "svtxt/*")
        } |
        Sort-Object
)

if ($rtlChanges.Count -eq 0) {
    Write-Host "RTL doc sync check: no RTL changes detected."
    exit 0
}

$errors = New-Object System.Collections.Generic.List[string]

foreach ($rtl in $rtlChanges) {
    $objects = Get-SvObjects -RepoRoot $repoRoot -RelPath $rtl
    if ($objects.Count -eq 0) {
        $errors.Add("${rtl}: no module/package declaration found; update docs/module_index.md or mark it as TBD.")
        continue
    }

    $expectedDocs = Get-ExpectedDocs -RelPath $rtl -Objects $objects
    foreach ($doc in $expectedDocs) {
        $docFull = Join-Path $repoRoot ($doc -replace "/", [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path $docFull)) {
            $errors.Add("${rtl}: expected documentation file missing: ${doc}")
            continue
        }
    }

    $touched = @($expectedDocs | Where-Object { $changedDocs.Contains($_) })
    if ($touched.Count -eq 0) {
        $errors.Add("${rtl}: RTL changed, but none of its expected docs changed. Expected one of: $($expectedDocs -join ', ')")
    }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "RTL/documentation sync check failed."
    Write-Host "Please update the matching Chinese module documentation whenever RTL changes."
    Write-Host "If the RTL edit does not affect behavior, touch the matching module doc and record that review note."
    Write-Host ""
    foreach ($err in $errors) {
        Write-Host " - $err"
    }
    Write-Host ""
    Write-Host "Manual check: powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-rtl-doc-sync.ps1"
    Write-Host "Pre-commit check: powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-rtl-doc-sync.ps1 -Staged"
    exit 1
}

Write-Host "RTL doc sync check passed."
