<#
.SYNOPSIS
Launches ClauseWeaver backend and frontend on Windows.
.DESCRIPTION
Uses the project virtual environment to start uvicorn and Vite, handles logging, and cleans up processes on exit.
#>
[CmdletBinding()]
param(
    [int]$BackendPort = 8000,
    [int]$FrontendPort = 5173,
    [switch]$BackendReload,
    [switch]$OpenBrowser,
    [string]$ProjectRoot,
    [string]$PythonCommand,
    [string]$TextFabricDataDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "[WARN] $Message"
}

function Resolve-Executable {
    param(
        [string]$Override,
        [string[]]$Candidates
    )

    if ($Override) {
        if (-not (Test-Path $Override)) {
            throw "Specified path not found: $Override"
        }
        return (Resolve-Path $Override).Path
    }

    foreach ($candidate in $Candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    return $null
}

function Ensure-PortFree {
    param(
        [int]$Port,
        [string]$Role
    )

    $listeners = @()
    try {
        $listeners = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop
    } catch {
        $listeners = @()
    }

    if (-not $listeners -or $listeners.Count -eq 0) {
        $pattern = ":{0} ".Replace('{0}', $Port.ToString())
        $netstat = & netstat -ano | Select-String -Pattern $pattern -SimpleMatch
        if ($netstat) {
            $listeners = $netstat | ForEach-Object {
                $line = $_.ToString()
                $parts = $line -split '\s+' | Where-Object { $_ }
                if ($parts.Length -ge 5) {
                    [pscustomobject]@{ OwningProcess = $parts[-1] }
                }
            } | Where-Object { $_ }
        }
    }

    if (-not $listeners -or $listeners.Count -eq 0) {
        return
    }

    $details = $listeners | ForEach-Object {
        $pid = $_.OwningProcess
        if ($pid -and ($pid -match '^\d+$')) {
            try {
                $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                if ($proc) {
                    return "PID $pid ($($proc.ProcessName))"
                }
            } catch {
                return "PID $pid"
            }
            return "PID $pid"
        }
        return 'Unknown process'
    } | Sort-Object -Unique

    throw "The $Role port $Port is already in use by: $([string]::Join(', ', $details))"
}

$repoRoot = if ($ProjectRoot) {
    (Resolve-Path $ProjectRoot).Path
} else {
    (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

Write-Info "Project root: $repoRoot"
$logsDir = Join-Path $repoRoot 'logs'
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir | Out-Null
}
$backendLog = Join-Path $logsDir 'backend.log'
$frontendLog = Join-Path $logsDir 'frontend.log'
'' | Set-Content $backendLog
'' | Set-Content $frontendLog

$pythonPath = Resolve-Executable -Override $PythonCommand -Candidates @((Join-Path $repoRoot '.venv\Scripts\python.exe'), 'python', 'py')
if (-not $pythonPath) {
    throw 'Python executable not found. Run Setup-ClauseWeaver.ps1 first.'
}

$npmPath = Resolve-Executable -Candidates @('npm')
if (-not $npmPath) {
    throw 'npm command not found. Verify the Node.js installation.'
}

$frontendDir = Join-Path $repoRoot 'frontend'
if (-not (Test-Path $frontendDir)) {
    throw "Frontend directory not found: $frontendDir"
}

$tfLocation = if ($TextFabricDataDir) {
    if (Test-Path $TextFabricDataDir) {
        (Resolve-Path $TextFabricDataDir).Path
    } else {
        Write-Warn "Specified Text-Fabric directory does not exist. It will be used as provided: $TextFabricDataDir"
        $TextFabricDataDir
    }
} elseif ($env:TF_DATA_LOCATION) {
    $env:TF_DATA_LOCATION
} else {
    Join-Path $HOME 'text-fabric-data'
}

$env:TF_DATA_LOCATION = $tfLocation
Write-Info "TF_DATA_LOCATION: $tfLocation"

Ensure-PortFree -Port $BackendPort -Role 'backend'
Ensure-PortFree -Port $FrontendPort -Role 'frontend'

Write-Step "Starting backend (uvicorn) on port $BackendPort"
$backendArgs = @('-m', 'uvicorn', 'backend.app:app', '--host', '0.0.0.0', '--port', $BackendPort, '--log-level', 'info', '--app-dir', $repoRoot)
if ($BackendReload) {
    $backendArgs += '--reload'
}
$backendProc = Start-Process -FilePath $pythonPath -ArgumentList $backendArgs -WorkingDirectory $repoRoot -RedirectStandardOutput $backendLog -RedirectStandardError $backendLog -PassThru
Start-Sleep -Seconds 2
if ($backendProc.HasExited) {
    $exitCode = $backendProc.ExitCode
    $backendOutput = Get-Content $backendLog -Tail 50
    throw "Backend process exited immediately (code $exitCode). Recent log:\n$backendOutput"
}
Write-Info "Backend PID: $($backendProc.Id)"

Write-Step "Starting frontend (Vite) on port $FrontendPort"
$frontendArgs = @('--prefix', $frontendDir, 'run', 'dev', '--', '--host', '0.0.0.0', '--port', $FrontendPort, '--strictPort')
$frontendProc = Start-Process -FilePath $npmPath -ArgumentList $frontendArgs -WorkingDirectory $repoRoot -RedirectStandardOutput $frontendLog -RedirectStandardError $frontendLog -PassThru
Start-Sleep -Seconds 2
if ($frontendProc.HasExited) {
    $exitCode = $frontendProc.ExitCode
    $frontendOutput = Get-Content $frontendLog -Tail 50
    throw "Frontend process exited immediately (code $exitCode). Recent log:\n$frontendOutput"
}
Write-Info "Frontend PID: $($frontendProc.Id)"

if ($OpenBrowser) {
    Write-Info "Opening browser: http://localhost:$FrontendPort"
    Start-Process "http://localhost:$FrontendPort"
}

Write-Info "Tail logs with: Get-Content -Wait '$backendLog' or '$frontendLog'"
Write-Info 'Close this window or press Ctrl+C to stop both services.'

try {
    while ($true) {
        Start-Sleep -Seconds 1
        if ($backendProc.HasExited) {
            Write-Warn 'Backend has stopped. Terminating frontend.'
            break
        }
        if ($frontendProc.HasExited) {
            Write-Warn 'Frontend has stopped. Terminating backend.'
            break
        }
    }
}
finally {
    foreach ($proc in @($frontendProc, $backendProc)) {
        if ($proc -and -not $proc.HasExited) {
            Write-Info "Stopping process PID $($proc.Id)"
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warn "Failed to stop process PID $($proc.Id)"
            }
        }
    }
    Write-Info "Backend log: $backendLog"
    Write-Info "Frontend log: $frontendLog"
}
