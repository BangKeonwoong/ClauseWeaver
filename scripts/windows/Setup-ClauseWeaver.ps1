<#
.SYNOPSIS
Automates ClauseWeaver environment setup on Windows.
.DESCRIPTION
Creates a Python virtual environment, installs project requirements, and downloads Text-Fabric data.
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

function Get-VersionFromOutput {
    param([string]$Text)
    if ($Text -match '(\d+\.\d+\.\d+)') {
        return [Version]$Matches[1]
    }
    throw "Unable to parse version from: $Text"
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
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logsDir "setup-$timestamp.log"
Start-Transcript -Path $logFile -Force | Out-Null

try {
    Write-Step 'Detect Python executable'
    $pythonPath = Resolve-Executable -Override $PythonCommand -Candidates @('python', 'py')
    if (-not $pythonPath) {
        throw 'Python executable not found. Install Python 3.12+ via Microsoft Store, winget, or the official installer.'
    }
    $pythonVersion = Get-VersionFromOutput -Text (& $pythonPath --version 2>&1)
    Write-Info "Python path: $pythonPath (version $pythonVersion)"
    if ($pythonVersion -lt [Version]'3.12.0') {
        throw 'Python 3.12 or newer is required. Install the latest version and re-run the script.'
    }

    Write-Step 'Detect Node.js (npm)'
    $nodePath = Resolve-Executable -Override $NodeCommand -Candidates @('node')
    if (-not $nodePath) {
        throw 'node executable not found. Install Node.js 20 LTS or newer.'
    }
    $nodeVersion = Get-VersionFromOutput -Text (& $nodePath --version 2>&1)
    Write-Info "Node.js path: $nodePath (version $nodeVersion)"
    if ($nodeVersion -lt [Version]'20.0.0') {
        throw 'Node.js 20 or newer is required. Update to the latest LTS release.'
    }

    $npmPath = Resolve-Executable -Candidates @('npm')
    if (-not $npmPath) {
        throw 'npm command not found. Verify the Node.js installation.'
    }
    Write-Info "npm path: $npmPath"

    Write-Step 'Prepare Python virtual environment'
    $venvDir = Join-Path $repoRoot '.venv'
    $venvPython = Join-Path $venvDir 'Scripts\python.exe'
    if (-not (Test-Path $venvPython)) {
        Write-Info 'Creating virtual environment (.venv).'
        & $pythonPath -m venv $venvDir
    } else {
        Write-Info 'Using existing virtual environment (.venv).'
    }

    if ($UpgradePip) {
        Write-Info 'Upgrading pip...'
        & $venvPython -m pip install --upgrade pip
    }

    Write-Step 'Install Python dependencies'
    Write-Info 'Installing backend package in editable mode.'
    & $venvPython -m pip install --upgrade wheel setuptools
    & $venvPython -m pip install -e (Join-Path $repoRoot 'backend')
    Write-Info 'Installing text-fabric package.'
    & $venvPython -m pip install text-fabric

    Write-Step 'Ensure Text-Fabric data availability'
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
        Write-Info "Creating Text-Fabric data directory: $tfDirPath"
        New-Item -ItemType Directory -Path $tfDirPath -Force | Out-Null
    }
    $targetDatasetDir = Join-Path $tfDirPath 'etcbc/bhsa/tf/2021'
    if ((Test-Path $targetDatasetDir) -and $SkipTextFabricDownload) {
        Write-Info 'Data already present; skipping download as requested.'
    } elseif (Test-Path $targetDatasetDir) {
        Write-Info "Detected existing dataset: $targetDatasetDir"
    } else {
        Write-Info 'Downloading Text-Fabric dataset (etcbc/bhsa/tf/2021).'
        $tfExe = Join-Path $venvDir 'Scripts\tf.exe'
        if (-not (Test-Path $tfExe)) {
            throw "tf CLI not found: $tfExe"
        }
        $env:TF_DATA_DIR = $tfDirPath
        & $tfExe get etcbc/bhsa/tf/2021
    }

    Write-Step 'Install Node.js dependencies'
    $frontendDir = Join-Path $repoRoot 'frontend'
    $nodeModulesDir = Join-Path $frontendDir 'node_modules'
    if ($ForceFrontendInstall -and (Test-Path $nodeModulesDir)) {
        Write-Info 'Removing existing node_modules (ForceFrontendInstall).'
        Remove-Item -Recurse -Force $nodeModulesDir
    }
    Write-Info 'Running npm install.'
    & $npmPath --prefix $frontendDir install

    Write-Info 'Setup complete.'
    Write-Info "Activate the virtual environment with: `& .venv\\Scripts\\Activate.ps1`"
    Write-Info "Text-Fabric data directory: $tfDirPath"
    Write-Info 'Use the launch script to start backend and frontend servers.'
}
catch {
    Write-Warn $_
    throw
}
finally {
    Stop-Transcript | Out-Null
    Write-Info "Setup log saved to: $logFile"
}
