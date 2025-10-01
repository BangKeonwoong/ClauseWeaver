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
            throw ("Specified path not found: {0}" -f $Override)
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

    $listenerCount = @($listeners).Count

    if ($listenerCount -eq 0) {
        $pattern = ":{0} ".Replace('{0}', $Port.ToString())
        $netstat = & netstat -ano | Select-String -Pattern $pattern -SimpleMatch
        if ($netstat) {
            $listeners = @($netstat | ForEach-Object {
                $line = $_.ToString()
                $parts = $line -split '\s+' | Where-Object { $_ }
                if ($parts.Length -ge 5) {
                    [pscustomobject]@{ OwningProcess = $parts[-1] }
                }
            } | Where-Object { $_ })
        }
        $listenerCount = @($listeners).Count
    }

    if ($listenerCount -eq 0) {
        return
    }

    $details = $listeners | ForEach-Object {
        $processId = $_.OwningProcess
        if ($processId -and ($processId -match '^\d+$')) {
            try {
                $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($proc) {
                    return ("PID {0} ({1})" -f $processId, $proc.ProcessName)
                }
            } catch {
                return ("PID {0}" -f $processId)
            }
            return ("PID {0}" -f $processId)
        }
        return 'Unknown process'
    } | Sort-Object -Unique

    throw ("The {0} port {1} is already in use by: {2}" -f $Role, $Port, ([string]::Join(', ', $details)))
}

$repoRoot = if ($ProjectRoot) {
    (Resolve-Path $ProjectRoot).Path
} else {
    (Get-Item -Path $PSScriptRoot).Parent.Parent.FullName
}

Write-Info ("Project root: {0}" -f $repoRoot)
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

$npmPath = Resolve-Executable -Candidates @('npm.cmd', 'npm')
if (-not $npmPath) {
    throw 'npm command not found. Verify the Node.js installation.'
}
if ($npmPath -like '*.ps1') {
    $cmdCandidate = [System.IO.Path]::ChangeExtension($npmPath, '.cmd')
    if ($cmdCandidate -and (Test-Path $cmdCandidate)) {
        $npmPath = $cmdCandidate
        Write-Info ("Using npm shim: {0}" -f $npmPath)
    }
}

$frontendDir = Join-Path $repoRoot 'frontend'
if (-not (Test-Path $frontendDir)) {
    throw ("Frontend directory not found: {0}" -f $frontendDir)
}

$tfLocation = if ($TextFabricDataDir) {
    if (Test-Path $TextFabricDataDir) {
        (Resolve-Path $TextFabricDataDir).Path
    } else {
        Write-Warn ("Specified Text-Fabric directory does not exist. Using as provided: {0}" -f $TextFabricDataDir)
        $TextFabricDataDir
    }
} elseif ($env:TF_DATA_LOCATION) {
    $env:TF_DATA_LOCATION
} else {
    Join-Path $HOME 'text-fabric-data'
}

$env:TF_DATA_LOCATION = $tfLocation
Write-Info ("TF_DATA_LOCATION: {0}" -f $tfLocation)

Ensure-PortFree -Port $BackendPort -Role 'backend'
Ensure-PortFree -Port $FrontendPort -Role 'frontend'

Write-Step ("Starting backend (uvicorn) on port {0}" -f $BackendPort)
$backendArgs = @('-m', 'uvicorn', 'backend.app:app', '--host', '0.0.0.0', '--port', $BackendPort, '--log-level', 'info', '--app-dir', $repoRoot)
if ($BackendReload) {
    $backendArgs += '--reload'
}
$backendProc = Start-Process -FilePath $pythonPath -ArgumentList $backendArgs -WorkingDirectory $repoRoot -RedirectStandardOutput $backendLog -RedirectStandardError $backendLog -PassThru
Start-Sleep -Seconds 2
if ($backendProc.HasExited) {
    $exitCode = $backendProc.ExitCode
    $backendOutput = Get-Content $backendLog -Tail 50
    throw ("Backend process exited immediately (code {0}). Recent log:\n{1}" -f $exitCode, ($backendOutput -join [Environment]::NewLine))
}
Write-Info ("Backend PID: {0}" -f $backendProc.Id)

Write-Step ("Starting frontend (Vite) on port {0}" -f $FrontendPort)
$frontendArgs = @('run', 'dev', '--', '--host', '0.0.0.0', '--port', $FrontendPort, '--strictPort')
$frontendProc = Start-Process -FilePath $npmPath -ArgumentList $frontendArgs -WorkingDirectory $frontendDir -RedirectStandardOutput $frontendLog -RedirectStandardError $frontendLog -PassThru
Start-Sleep -Seconds 2
if ($frontendProc.HasExited) {
    $exitCode = $frontendProc.ExitCode
    $frontendOutput = Get-Content $frontendLog -Tail 50
    throw ("Frontend process exited immediately (code {0}). Recent log:\n{1}" -f $exitCode, ($frontendOutput -join [Environment]::NewLine))
}
Write-Info ("Frontend PID: {0}" -f $frontendProc.Id)

if ($OpenBrowser) {
    Write-Info ("Opening browser at http://localhost:{0}" -f $FrontendPort)
    Start-Process ("http://localhost:{0}" -f $FrontendPort)
}

Write-Info ("Tail logs with: Get-Content -Wait '{0}' or '{1}'" -f $backendLog, $frontendLog)
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
            Write-Info ("Stopping process PID {0}" -f $proc.Id)
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warn ("Failed to stop process PID {0}" -f $proc.Id)
            }
        }
    }
    Write-Info ("Backend log: {0}" -f $backendLog)
    Write-Info ("Frontend log: {0}" -f $frontendLog)
}
