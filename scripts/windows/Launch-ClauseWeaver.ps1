<#
.SYNOPSIS
ClauseWeaver 백엔드와 프런트엔드를 Windows에서 원클릭으로 실행합니다.
.DESCRIPTION
가상환경을 사용해 uvicorn과 Vite 개발 서버를 시작하고 로그 파일을 관리하며, 종료 시 프로세스를 정리합니다.
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
    Write-Host "[단계] $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[정보] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "[경고] $Message"
}

function Resolve-Executable {
    param(
        [string]$Override,
        [string[]]$Candidates
    )

    if ($Override) {
        if (-not (Test-Path $Override)) {
            throw "명시된 경로를 찾을 수 없습니다: $Override"
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
        return '알 수 없는 프로세스'
    } | Sort-Object -Unique

    throw "${Role} 포트 ${Port}가 이미 사용 중입니다: $([string]::Join(', ', $details))"
}

$repoRoot = if ($ProjectRoot) {
    (Resolve-Path $ProjectRoot).Path
} else {
    (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
}

Write-Info "프로젝트 루트: $repoRoot"
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
    throw 'Python 실행 파일을 찾을 수 없습니다. 먼저 Setup-ClauseWeaver.ps1 스크립트를 실행하세요.'
}

$npmPath = Resolve-Executable -Candidates @('npm')
if (-not $npmPath) {
    throw 'npm 명령을 찾을 수 없습니다. Node.js 설치 상태를 확인하세요.'
}

$frontendDir = Join-Path $repoRoot 'frontend'
if (-not (Test-Path $frontendDir)) {
    throw "프런트엔드 디렉토리를 찾을 수 없습니다: $frontendDir"
}

$tfLocation = if ($TextFabricDataDir) {
    if (Test-Path $TextFabricDataDir) {
        (Resolve-Path $TextFabricDataDir).Path
    } else {
        Write-Warn "지정한 Text-Fabric 경로가 존재하지 않습니다. 실행 중 생성될 수 있습니다: $TextFabricDataDir"
        $TextFabricDataDir
    }
} elseif ($env:TF_DATA_LOCATION) {
    $env:TF_DATA_LOCATION
} else {
    Join-Path $HOME 'text-fabric-data'
}

$env:TF_DATA_LOCATION = $tfLocation
Write-Info "TF_DATA_LOCATION: $tfLocation"

Ensure-PortFree -Port $BackendPort -Role '백엔드'
Ensure-PortFree -Port $FrontendPort -Role '프런트엔드'

Write-Step "백엔드 (uvicorn) 시작: 포트 $BackendPort"
$backendArgs = @('-m', 'uvicorn', 'backend.app:app', '--host', '0.0.0.0', '--port', $BackendPort, '--log-level', 'info', '--app-dir', $repoRoot)
if ($BackendReload) {
    $backendArgs += '--reload'
}
$backendProc = Start-Process -FilePath $pythonPath -ArgumentList $backendArgs -WorkingDirectory $repoRoot -RedirectStandardOutput $backendLog -RedirectStandardError $backendLog -PassThru
Start-Sleep -Seconds 2
if ($backendProc.HasExited) {
    $exitCode = $backendProc.ExitCode
    $backendOutput = Get-Content $backendLog -Tail 50
    throw "백엔드 프로세스가 즉시 종료되었습니다 (코드 $exitCode). 로그:\n$backendOutput"
}
Write-Info "백엔드 PID: $($backendProc.Id)"

Write-Step "프런트엔드 (Vite) 시작: 포트 $FrontendPort"
$frontendArgs = @('--prefix', $frontendDir, 'run', 'dev', '--', '--host', '0.0.0.0', '--port', $FrontendPort, '--strictPort')
$frontendProc = Start-Process -FilePath $npmPath -ArgumentList $frontendArgs -WorkingDirectory $repoRoot -RedirectStandardOutput $frontendLog -RedirectStandardError $frontendLog -PassThru
Start-Sleep -Seconds 2
if ($frontendProc.HasExited) {
    $exitCode = $frontendProc.ExitCode
    $frontendOutput = Get-Content $frontendLog -Tail 50
    throw "프런트엔드 프로세스가 즉시 종료되었습니다 (코드 $exitCode). 로그:\n$frontendOutput"
}
Write-Info "프런트엔드 PID: $($frontendProc.Id)"

if ($OpenBrowser) {
    Write-Info "브라우저를 자동으로 엽니다: http://localhost:$FrontendPort"
    Start-Process "http://localhost:$FrontendPort"
}

Write-Info "실시간 로그: `Get-Content -Wait '$backendLog'`, `Get-Content -Wait '$frontendLog'`"
Write-Info '종료하려면 Ctrl+C 또는 PowerShell 창을 닫으세요.'

try {
    while ($true) {
        Start-Sleep -Seconds 1
        if ($backendProc.HasExited) {
            Write-Warn '백엔드 프로세스가 종료되었습니다. 프런트엔드도 정리합니다.'
            break
        }
        if ($frontendProc.HasExited) {
            Write-Warn '프런트엔드 프로세스가 종료되었습니다. 백엔드도 정리합니다.'
            break
        }
    }
}
finally {
    foreach ($proc in @($frontendProc, $backendProc)) {
        if ($proc -and -not $proc.HasExited) {
            Write-Info "프로세스 종료 중: PID $($proc.Id)"
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warn "프로세스 종료 실패: PID $($proc.Id)"
            }
        }
    }
    Write-Info "백엔드 로그: $backendLog"
    Write-Info "프런트엔드 로그: $frontendLog"
}
