param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'workday-startup.json'),
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 输出分段标题，方便在终端里区分不同启动阶段。
function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message =="
}

function Invoke-Launch {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    # DryRun 模式只打印计划动作，不真正启动程序。
    if ($DryRun) {
        Write-Host "[DryRun] $Name"
        return
    }

    & $Action
    Write-Host "[Started] $Name"
}

function Resolve-CommandPath {
    param(
        [string]$ConfiguredPath,
        [string]$CommandName
    )

    # 优先使用配置里显式指定的路径，没有时再走 PATH 搜索。
    if ($ConfiguredPath) {
        if (Test-Path -LiteralPath $ConfiguredPath) {
            return (Resolve-Path -LiteralPath $ConfiguredPath).Path
        }

        throw "Configured path does not exist: $ConfiguredPath"
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Start-Codex {
    param([pscustomobject]$Config)

    # Codex 支持 exe 直启和 appId 启动两种模式。
    if (-not $Config.enabled) {
        Write-Host "[Skip] Codex disabled"
        return
    }

    $launchMode = $Config.launchMode
    if (-not $launchMode) {
        $launchMode = 'auto'
    }

    $candidateExePaths = @()
    if ($Config.exePath) {
        $candidateExePaths += $Config.exePath
    }
    $candidateExePaths += @(
        "$env:LOCALAPPDATA\Programs\codex\Codex.exe",
        "$env:LOCALAPPDATA\Programs\Codex\Codex.exe"
    )

    $resolvedExePath = $candidateExePaths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    $appId = $Config.appId
    if (-not $appId) {
        $appId = 'OpenAI.Codex_2p2nqsd0c76g0!App'
    }

    if ($launchMode -eq 'exe' -or ($launchMode -eq 'auto' -and $resolvedExePath)) {
        Invoke-Launch -Name 'Codex' -Action {
            Start-Process -FilePath $resolvedExePath | Out-Null
        }
        return
    }

    if ($launchMode -eq 'appId' -or $launchMode -eq 'auto') {
        Invoke-Launch -Name 'Codex' -Action {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$appId" | Out-Null
        }
        return
    }

    throw "Unable to determine how to launch Codex. Check the 'codex' section in the config file."
}

function Start-Chrome {
    param([pscustomobject]$Config)

    # 启动预设网页集合，可选绑定指定 Chrome profile。
    if (-not $Config.enabled) {
        Write-Host "[Skip] Chrome disabled"
        return
    }

    $chromePath = Resolve-CommandPath -ConfiguredPath $Config.exePath -CommandName 'chrome'
    if (-not $chromePath) {
        $fallbacks = @(
            'C:\Program Files\Google\Chrome\Application\chrome.exe',
            'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
        )
        $chromePath = $fallbacks | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }

    if (-not $chromePath) {
        throw 'Chrome executable was not found.'
    }

    $urls = @($Config.urls | Where-Object { $_ })
    if ($urls.Count -eq 0) {
        Write-Host '[Skip] No Chrome URLs configured'
        return
    }

    $arguments = @()
    if ($Config.profileDirectory) {
        $arguments += "--profile-directory=$($Config.profileDirectory)"
    }
    $arguments += '--new-window'
    $arguments += $urls

    Invoke-Launch -Name 'Chrome pages' -Action {
        Start-Process -FilePath $chromePath -ArgumentList $arguments | Out-Null
    }
}

function Start-VSCode {
    param([pscustomobject]$Config)

    # 在同一 VS Code 窗口里复用打开多个工程或文件目标。
    if (-not $Config.enabled) {
        Write-Host "[Skip] VS Code disabled"
        return
    }

    $codePath = Resolve-CommandPath -ConfiguredPath $Config.commandPath -CommandName 'code'
    if (-not $codePath) {
        throw 'VS Code command was not found.'
    }

    $targets = @($Config.targets | Where-Object { $_ })
    if ($targets.Count -eq 0) {
        Write-Host '[Skip] No VS Code targets configured'
        return
    }

    $missingTargets = @($targets | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missingTargets.Count -gt 0) {
        throw "These VS Code targets do not exist: $($missingTargets -join ', ')"
    }

    $arguments = @('-r') + $targets
    Invoke-Launch -Name 'VS Code' -Action {
        Start-Process -FilePath $codePath -ArgumentList $arguments | Out-Null
    }
}

function Start-Documents {
    param([pscustomobject]$Config)

    # 文档可交给系统默认程序，也可统一交给 VS Code 打开。
    if (-not $Config.enabled) {
        Write-Host "[Skip] Documents disabled"
        return
    }

    $paths = @($Config.paths | Where-Object { $_ })
    if ($paths.Count -eq 0) {
        Write-Host '[Skip] No document paths configured'
        return
    }

    $missingPaths = @($paths | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missingPaths.Count -gt 0) {
        throw "These document paths do not exist: $($missingPaths -join ', ')"
    }

    $openWith = $Config.openWith
    if (-not $openWith) {
        $openWith = 'default'
    }

    if ($openWith -eq 'vscode') {
        $codePath = Resolve-CommandPath -ConfiguredPath $Config.commandPath -CommandName 'code'
        if (-not $codePath) {
            throw 'VS Code command was not found for opening documents.'
        }

        $arguments = @('-r') + $paths
        Invoke-Launch -Name 'Configured documents in VS Code' -Action {
            Start-Process -FilePath $codePath -ArgumentList $arguments | Out-Null
        }
        return
    }

    foreach ($path in $paths) {
        $name = "Document: $path"
        Invoke-Launch -Name $name -Action {
            Start-Process -FilePath $path | Out-Null
        }
    }
}

# 配置文件缺失时直接失败，避免用户误以为脚本已经执行成功。
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

Write-Section "Using config"
Write-Host $ConfigPath

Start-Codex -Config $config.codex
Start-Chrome -Config $config.chrome
Start-VSCode -Config $config.vscode
Start-Documents -Config $config.documents

Write-Section "Done"
if ($DryRun) {
    Write-Host 'Dry run completed. No apps were launched.'
} else {
    Write-Host 'Startup sequence completed.'
}
