<#
.SYNOPSIS
ClauseWeaver 개발 환경을 Windows에서 자동으로 구성합니다.
.DESCRIPTION
Python, Node.js, Text-Fabric 데이터 및 프로젝트 의존성을 설치하고 구성합니다.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$PythonCommand,
    [string]$NodeCommand,
    [string]$TextFabricDataDir,
    [switch]$SkipTextFabricDownload,
    [switch]$ForceFrontendInstall,
    [switch]$UpgradePip
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

function Get-VersionFromOutput {
    param([string]$Text)
    if ($Text -match '(\d+\.\d+\.\d+)') {
        return [Version]$Matches[1]
    }
    throw "버전을 파싱할 수 없습니다: $Text"
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
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logsDir "setup-$timestamp.log"
Start-Transcript -Path $logFile -Force | Out-Null

try {
    Write-Step 'Python 실행 파일 확인'
    $pythonPath = Resolve-Executable -Override $PythonCommand -Candidates @('python', 'py')
    if (-not $pythonPath) {
        throw 'Python 실행 파일을 찾을 수 없습니다. Microsoft Store, winget, 또는 설치 프로그램을 통해 Python 3.12 이상을 설치하세요.'
    }
    $pythonVersion = Get-VersionFromOutput -Text (& $pythonPath --version 2>&1)
    Write-Info "Python 경로: $pythonPath (버전: $pythonVersion)"
    if ($pythonVersion -lt [Version]'3.12.0') {
        throw 'Python 3.12 이상이 필요합니다. 최신 버전을 설치한 뒤 다시 실행하세요.'
    }

    Write-Step 'Node.js (npm) 확인'
    $nodePath = Resolve-Executable -Override $NodeCommand -Candidates @('node')
    if (-not $nodePath) {
        throw 'node 실행 파일을 찾을 수 없습니다. Node.js 20 LTS 이상을 설치하세요.'
    }
    $nodeVersion = Get-VersionFromOutput -Text (& $nodePath --version 2>&1)
    Write-Info "Node.js 경로: $nodePath (버전: $nodeVersion)"
    if ($nodeVersion -lt [Version]'20.0.0') {
        throw 'Node.js 20 이상이 필요합니다. 최신 LTS 버전으로 업데이트하세요.'
    }

    $npmPath = Resolve-Executable -Candidates @('npm')
    if (-not $npmPath) {
        throw 'npm 명령을 찾을 수 없습니다. Node.js 설치가 올바르게 완료되었는지 확인하세요.'
    }
    Write-Info "npm 경로: $npmPath"

    Write-Step '가상환경 준비'
    $venvDir = Join-Path $repoRoot '.venv'
    $venvPython = Join-Path $venvDir 'Scripts\python.exe'
    if (-not (Test-Path $venvPython)) {
        Write-Info '가상환경을 생성합니다 (.venv).'
        & $pythonPath -m venv $venvDir
    } else {
        Write-Info '기존 가상환경을 재사용합니다.'
    }

    if ($UpgradePip) {
        Write-Info 'pip 업그레이드 중...'
        & $venvPython -m pip install --upgrade pip
    }

    Write-Step 'Python 의존성 설치'
    Write-Info 'backend 패키지를 편집 가능 모드로 설치합니다.'
    & $venvPython -m pip install --upgrade wheel setuptools
    & $venvPython -m pip install -e (Join-Path $repoRoot 'backend')
    Write-Info 'text-fabric 패키지를 설치합니다.'
    & $venvPython -m pip install text-fabric

    Write-Step 'Text-Fabric 데이터 확인'
    $tfDir = if ($TextFabricDataDir) {
        (Resolve-Path -Path $TextFabricDataDir -ErrorAction SilentlyContinue)
    } else {
        $null
    }
    if (-not $tfDir) {
        $tfDir = Join-Path $HOME 'text-fabric-data'
    }
    $tfDirPath = $tfDir
    if (-not (Test-Path $tfDirPath)) {
        Write-Info "Text-Fabric 데이터 디렉토리를 생성합니다: $tfDirPath"
        New-Item -ItemType Directory -Path $tfDirPath -Force | Out-Null
    }
    $targetDatasetDir = Join-Path $tfDirPath 'etcbc/bhsa/tf/2021'
    if ((Test-Path $targetDatasetDir) -and $SkipTextFabricDownload) {
        Write-Info '데이터가 이미 존재하며 다운로드를 건너뜁니다.'
    } elseif (Test-Path $targetDatasetDir) {
        Write-Info "이미 다운로드된 데이터가 감지되었습니다: $targetDatasetDir"
    } else {
        Write-Info 'Text-Fabric 데이터를 다운로드합니다 (etcbc/bhsa/tf/2021).'
        $tfExe = Join-Path $venvDir 'Scripts\tf.exe'
        if (-not (Test-Path $tfExe)) {
            throw "tf CLI를 찾을 수 없습니다: $tfExe"
        }
        $env:TF_DATA_DIR = $tfDirPath
        & $tfExe get etcbc/bhsa/tf/2021
    }

    Write-Step 'Node.js 의존성 설치'
    $frontendDir = Join-Path $repoRoot 'frontend'
    $nodeModulesDir = Join-Path $frontendDir 'node_modules'
    if ($ForceFrontendInstall -and (Test-Path $nodeModulesDir)) {
        Write-Info '기존 node_modules 디렉토리를 정리합니다 (-ForceFrontendInstall).'
        Remove-Item -Recurse -Force $nodeModulesDir
    }
    Write-Info 'npm install을 실행합니다.'
    & $npmPath --prefix $frontendDir install

    Write-Info '설치가 완료되었습니다.'
    Write-Info "가상환경 활성화: `& .venv\\Scripts\\Activate.ps1`"
    Write-Info "Text-Fabric 데이터 위치: $tfDirPath"
    Write-Info '프런트엔드 개발 서버는 별도 실행 스크립트를 사용하세요.'
}
catch {
    Write-Warn $_
    throw
}
finally {
    Stop-Transcript | Out-Null
    Write-Info "설치 로그 파일: $logFile"
}
