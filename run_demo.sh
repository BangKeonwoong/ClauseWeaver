#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
BACKEND_RELOAD="${BACKEND_RELOAD:-0}"
LOG_DIR="${DIR}/logs"
BACKEND_LOG="${LOG_DIR}/backend.log"
FRONTEND_LOG="${LOG_DIR}/frontend.log"

BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
  trap - EXIT INT TERM
  if [[ -n "${FRONTEND_PID}" ]]; then
    kill "${FRONTEND_PID}" 2>/dev/null || true
  fi
  if [[ -n "${BACKEND_PID}" ]]; then
    kill "${BACKEND_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

if ! command -v uvicorn >/dev/null 2>&1; then
  echo "[오류] uvicorn 명령을 찾을 수 없습니다. Python 가상환경이 활성화됐는지 확인하세요." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "[오류] npm 명령을 찾을 수 없습니다. Node.js를 설치하거나 PATH를 확인하세요." >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
echo "" > "${BACKEND_LOG}"
echo "" > "${FRONTEND_LOG}"

if [[ ! -d "${DIR}/frontend/node_modules" ]]; then
  echo "[정보] 프런트엔드 의존성을 설치합니다..." | tee -a "${FRONTEND_LOG}"
  npm --prefix "${DIR}/frontend" install 2>&1 | tee -a "${FRONTEND_LOG}"
fi

reload_note="비활성화"
uvicorn_args=("backend.app:app" "--host" "0.0.0.0" "--port" "${BACKEND_PORT}" "--log-level" "info" "--app-dir" "${DIR}")
if [[ "${BACKEND_RELOAD}" =~ ^(1|true|TRUE|yes|YES)$ ]]; then
  uvicorn_args+=("--reload")
  reload_note="활성화"
fi

echo "[정보] 백엔드(uvicorn) 서버를 ${BACKEND_PORT} 포트에서 시작합니다. (리로드: ${reload_note})"
echo "[정보] 백엔드 로그 파일: ${BACKEND_LOG}"
if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"${BACKEND_PORT}" -sTCP:LISTEN >/tmp/backend_port_check.$$ 2>/dev/null; then
    echo "[오류] 백엔드 포트 ${BACKEND_PORT}를 점유 중인 프로세스가 있습니다:" | tee -a "${BACKEND_LOG}" >&2
    cat /tmp/backend_port_check.$$ | tee -a "${BACKEND_LOG}"
    rm -f /tmp/backend_port_check.$$
    exit 1
  fi
  rm -f /tmp/backend_port_check.$$
fi

uvicorn "${uvicorn_args[@]}" >> "${BACKEND_LOG}" 2>&1 &
BACKEND_PID=$!

sleep 1

if ! kill -0 "${BACKEND_PID}" >/dev/null 2>&1; then
  echo "[오류] 백엔드 서버가 예기치 않게 종료되었습니다." >&2
  wait "${BACKEND_PID}" 2>/dev/null || true
  exit 1
fi

if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"${FRONTEND_PORT}" -sTCP:LISTEN >/tmp/vite_port_check.$$ 2>/dev/null; then
    echo "[오류] 포트 ${FRONTEND_PORT}를 점유 중인 프로세스가 있습니다:" | tee -a "${FRONTEND_LOG}" >&2
    cat /tmp/vite_port_check.$$ | tee -a "${FRONTEND_LOG}"
    rm -f /tmp/vite_port_check.$$
    exit 1
  fi
  rm -f /tmp/vite_port_check.$$
fi

echo "[정보] 프런트엔드(Vite)를 ${FRONTEND_PORT} 포트에서 시작합니다."
echo "[정보] 프런트엔드 로그 파일: ${FRONTEND_LOG}"
npm --prefix "${DIR}/frontend" run dev -- --host 0.0.0.0 --port "${FRONTEND_PORT}" --strictPort \
  >> "${FRONTEND_LOG}" 2>&1 &
FRONTEND_PID=$!

sleep 1

if ! kill -0 "${FRONTEND_PID}" >/dev/null 2>&1; then
  echo "[오류] 프런트엔드 서버가 예상보다 빨리 종료되었습니다. 로그 파일을 확인하세요: ${FRONTEND_LOG}" >&2
  wait "${FRONTEND_PID}" 2>/dev/null || true
  exit 1
fi

echo "[정보] 프런트엔드/백엔드 로그 모니터링: tail -f '${BACKEND_LOG}' '${FRONTEND_LOG}'"

wait "${BACKEND_PID}" 2>/dev/null || true

if kill -0 "${FRONTEND_PID}" >/dev/null 2>&1; then
  echo "[정보] 백엔드 종료를 감지했습니다. 프런트엔드 프로세스를 종료합니다."
  kill "${FRONTEND_PID}" 2>/dev/null || true
fi

wait "${FRONTEND_PID}" 2>/dev/null || true
