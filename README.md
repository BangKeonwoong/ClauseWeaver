# ClauseWeaver

BHSA(Biblia Hebraica Stuttgartensia) 절(clause)의 어미 관계를 재구성하고 주석을 남길 수 있는 FastAPI + React 기반 툴입니다. Text-Fabric 데이터를 로드해 원본 구조를 보존하면서 드래그 앤 드롭으로 어미 절을 재배치하고, 선택한 절의 메타데이터와 주석을 사이드 패널에서 확인할 수 있습니다.

## 요구 사항

- Python 3.12+
- Node.js 20+
- Text-Fabric 데이터(`etcbc/bhsa/tf/2021`) 다운로드 (기본 경로: `~/text-fabric-data`)

## 설치

먼저 Text-Fabric 데이터를 받아둡니다.

```bash
pip install text-fabric  # tf CLI 설치
mkdir -p ~/text-fabric-data
cd ~/text-fabric-data
tf get etcbc/bhsa/tf/2021
```

다른 경로에 다운로드했다면 `TF_DATA_LOCATION` 환경 변수를 해당 경로로 설정하거나 `backend` 코드에서 `ConfigOptions.tf_location`을 조정하세요.

```bash
git clone git@github.com:BangKeonwoong/ClauseWeaver.git
cd ClauseWeaver

# Python
python3 -m venv .venv
source .venv/bin/activate
pip install -e backend

# Node
npm --prefix frontend install
```

## 실행

```bash
source .venv/bin/activate
./run_demo.sh
```

기본 포트는 백엔드 8000, 프런트엔드 5173입니다. 실행 시 `logs/` 디렉토리에 각각의 로그가 생성되며, 종료 시 자동 정리됩니다.

## Windows 원클릭 실행

### 초기 설정
- 관리자 권한이 필요하지 않은 일반 PowerShell 창에서 프로젝트 루트로 이동한 뒤 `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Setup-ClauseWeaver.ps1`를 실행합니다.
- `-UpgradePip`(pip 최신화), `-ForceFrontendInstall`(기존 node_modules 재설치), `-SkipTextFabricDownload` 등의 스위치로 세부 동작을 조정할 수 있습니다.
- Text-Fabric 데이터는 기본적으로 `%USERPROFILE%\text-fabric-data`에 설치되며, 다른 경로를 사용하려면 `-TextFabricDataDir`로 지정합니다.

### 실행
- `scripts\windows\start_clauseweaver.cmd`를 더블 클릭하거나 터미널에서 `.\scripts\windows\start_clauseweaver.cmd -OpenBrowser`를 호출하면 백엔드/프런트 서버가 동시에 시작됩니다.
- 추가 인자가 필요하면 직접 PowerShell 스크립트를 호출합니다: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Launch-ClauseWeaver.ps1 -BackendReload -BackendPort 8001`.

### 로그와 종료
- 설치 로그는 `logs/setup-YYYYMMDD-HHmmss.log`, 실행 로그는 `logs/backend.log`, `logs/frontend.log`에 저장됩니다.
- 창을 닫거나 Ctrl+C를 누르면 두 프로세스가 모두 종료되며, 포트 충돌 시 어떤 프로세스가 사용 중인지 메시지로 안내합니다.

## 테스트

```bash
source .venv/bin/activate
PYTHONPATH=. pytest backend/tests/test_mother.py -q
```

## 프로젝트 구조

```
ClauseWeaver
├── backend           # FastAPI, Text-Fabric 연동 및 검증 로직
├── frontend          # React + TypeScript UI
├── docs              # 설계 문서
└── run_demo.sh       # 백엔드/프런트 실행 스크립트
```

## 주요 기능

- BHSA 절/어미 관계 로딩 및 시각화
- 드래그 앤 드롭을 통한 어미 절 수정
- 선택 절의 typ/rela/code/txt/핵심 기능 등 메타데이터 표시
- 선택 절, 부모, 자식, 형제 절 하이라이트
- 절별 주석 및 체크리스트 기록

## 라이선스

MIT License (필요 시 조정)
