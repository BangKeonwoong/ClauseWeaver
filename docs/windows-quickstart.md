# Windows Quickstart

ClauseWeaver를 Windows에서 원클릭으로 실행하기 위한 PowerShell/Batch 스크립트 사용 가이드입니다.

## 준비

1. Git으로 프로젝트를 클론합니다.
2. PowerShell(관리자 권한 필요 없음)을 열고 저장소 루트로 이동합니다.
3. 스크립트 실행 정책이 제한되어 있다면, 개별 실행에서만 예외를 허용하기 위해 `-ExecutionPolicy Bypass` 옵션을 사용합니다.

## Setup-ClauseWeaver.ps1

`./scripts/windows/Setup-ClauseWeaver.ps1`는 Python 가상환경과 Node.js 의존성을 설치하고, Text-Fabric 데이터를 내려받습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Setup-ClauseWeaver.ps1
```

### 주요 옵션

- `-UpgradePip`: 가상환경 생성 후 `pip`을 최신 버전으로 올립니다.
- `-TextFabricDataDir "D:\\text-fabric"`: 기본 경로 대신 사용자 지정 위치에 데이터를 저장합니다.
- `-SkipTextFabricDownload`: 이미 데이터를 내려받았다면 다운로드 단계를 생략합니다.
- `-ForceFrontendInstall`: `frontend/node_modules`를 삭제한 뒤 재설치합니다.

실행 결과는 `logs/setup-YYYYMMDD-HHmmss.log`에 저장됩니다.

## Launch-ClauseWeaver.ps1

`./scripts/windows/Launch-ClauseWeaver.ps1`는 uvicorn 백엔드와 Vite 프런트엔드를 동시에 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Launch-ClauseWeaver.ps1 -OpenBrowser
```

### 매개변수

- `-BackendPort`, `-FrontendPort`: 기본 포트(8000/5173)를 변경합니다.
- `-BackendReload`: `uvicorn --reload`를 활성화합니다.
- `-TextFabricDataDir`: 실행 시점에 사용할 `TF_DATA_LOCATION` 값을 지정합니다.
- `-PythonCommand "C:\\Program Files\\Python312\\python.exe"`: 특정 Python 실행 파일을 사용합니다.

로그는 `logs/backend.log`, `logs/frontend.log`에 기록되며, 포트가 이미 사용 중이면 관련 프로세스 PID를 안내합니다.

## start_clauseweaver.cmd

`./scripts/windows/start_clauseweaver.cmd`는 Launch 스크립트를 감싼 배치 파일입니다. 더블 클릭으로 실행하거나 터미널에서 옵션을 그대로 전달할 수 있습니다.

```cmd
scripts\windows\start_clauseweaver.cmd -OpenBrowser
```

## 문제 해결

- Python 또는 Node.js가 감지되지 않으면 `winget`, `choco`, 혹은 공식 설치 프로그램으로 최신 버전을 설치한 뒤 다시 실행하세요.
- 실행 로그가 즉시 종료되면 `logs/backend.log`, `logs/frontend.log`의 마지막 줄을 확인하고, 포트 충돌이 발생했다면 안내된 PID를 종료한 후 재시도합니다.
- Text-Fabric 데이터가 존재하지 않거나 손상된 경우 `-SkipTextFabricDownload`를 빼고 Setup 스크립트를 다시 실행하면 자동으로 다운로드합니다.

## 다음 단계

Windows에서 구동이 확인되면 동일한 구조로 macOS용 셸 스크립트를 추가하여 양 플랫폼에서 일관된 실행 경험을 제공할 수 있습니다.
