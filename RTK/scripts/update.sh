#!/usr/bin/env bash
#
# RTK 업데이트 (macOS / Linux)
#   사용법: ./update.sh [옵션]         Windows는 update.ps1
#
# 확인 기준: RTK v1.0.1 · 2026-10-22 · macOS 기본 bash 3.2에서 동작
# 설치되어 있을 때만 최신으로 올린다. 새로 설치하지 않는다.
#   바이너리: Homebrew로 설치했으면 brew upgrade rtk, 아니면 공식 설치 스크립트를 다시 실행
#   연결:     이미 연결된 에이전트만 같은 방식으로 다시 연결한다.
#             새 버전의 지시문(RTK.md)을 받기 위해서다. 다시 연결해도 훅은 하나만 남는다 (2026-10-22 확인).

set -u

SCRIPT_VERSION="2026-10-22"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
BACKUP_ROOT="$HOME/.ai_tokens_backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-rtk-update"
RTK_INSTALL_URL="https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"
RTK_LATEST_API="https://api.github.com/repos/rtk-ai/rtk/releases/latest"

DRY_RUN=0
ASSUME_YES=0
FAILED=""

# ---------- 공통 헬퍼 ----------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_B="$(printf '\033[1m')"; C_R="$(printf '\033[31m')"
  C_Y="$(printf '\033[33m')"; C_G="$(printf '\033[32m')"; C_0="$(printf '\033[0m')"
else
  C_B=""; C_R=""; C_Y=""; C_G=""; C_0=""
fi

step() { printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s[OK]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '    %s[주의]%s %s\n' "$C_Y" "$C_0" "$*"; }
err()  { printf '    %s[실패]%s %s\n' "$C_R" "$C_0" "$*"; }
die()  { printf '\n%s[중단]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
fail() { err "$*"; FAILED="$FAILED
      - $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# "rtk 1.0.1" 같은 출력에서 버전 숫자만 꺼낸다
rtk_version() { rtk --version 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1; }

# GitHub의 최신 정식 릴리스 버전 (실패하면 빈 값)
latest_version() {
  have curl || return 0
  curl -fsSL --max-time 10 "$RTK_LATEST_API" 2>/dev/null \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' | head -1
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '    [dry-run] %s\n' "$*"; return 0; fi
  printf '    $ %s\n' "$*"
  "$@"
}

run_shell() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '    [dry-run] %s\n' "$1"; return 0; fi
  printf '    $ %s\n' "$1"
  sh -c "$1"
}

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ "$DRY_RUN" -eq 1 ] && return 0
  printf '\n계속할까요? [y/N] '
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) die "사용자가 취소했습니다." ;; esac
}

usage() {
  cat <<'EOF'
RTK 업데이트 (macOS / Linux)

  ./update.sh               설치된 RTK를 최신으로 올리고 기존 연결을 다시 맺음

옵션
  -y, --yes       확인 질문 없이 진행
      --dry-run   실행할 명령만 출력 (아무것도 바꾸지 않음)
  -h, --help      이 도움말

하는 일
  1. 설치된 버전과 GitHub 최신 버전 비교 (같으면 끝)
  2. 바이너리: brew upgrade rtk (Homebrew 설치일 때) / 공식 설치 스크립트 재실행
  3. 연결이 있던 에이전트만 다시 연결
       Claude Code  rtk init -g --auto-patch  (훅만 쓰던 경우 --hook-only 유지)
       Codex        rtk init -g --codex
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "알 수 없는 옵션: $1" ;;
  esac
  shift
done

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) die "지원하지 않는 OS: $(uname -s). Windows에서는 update.ps1을 쓰세요." ;;
esac

# ---------- 실행 ----------

printf '%sRTK 업데이트%s (%s, %s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION" "$OS"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 아무것도 바꾸지 않습니다."

if ! have rtk; then
  ok "RTK가 설치되어 있지 않아 올릴 것이 없습니다. 설치는 ./install.sh"
  exit 0
fi

CURRENT="$(rtk_version)"
LATEST="$(latest_version)"
info "설치된 버전: ${CURRENT:-확인 실패} ($(command -v rtk))"
info "최신 버전:   ${LATEST:-확인 실패 (네트워크 확인)}"

CLAUDE_HOOK=0; grep -q 'rtk hook' "$HOME/.claude/settings.json" 2>/dev/null && CLAUDE_HOOK=1
CLAUDE_MD=0;   [ -f "$HOME/.claude/RTK.md" ] && CLAUDE_MD=1
CODEX_HOOK=0;  grep -q 'rtk hook' "$CODEX_DIR/hooks.json" 2>/dev/null && CODEX_HOOK=1
info "연결: Claude Code=$([ "$CLAUDE_HOOK" -eq 1 ] && { [ "$CLAUDE_MD" -eq 1 ] && echo '훅+RTK.md' || echo '훅만'; } || echo 없음), Codex=$([ "$CODEX_HOOK" -eq 1 ] && echo 훅 || echo 없음)"

if [ -n "$CURRENT" ] && [ -n "$LATEST" ] && [ "$CURRENT" = "$LATEST" ]; then
  ok "이미 최신입니다."
  exit 0
fi

confirm

step "설정 백업"
info "위치: $BACKUP_DIR"
run mkdir -p "$BACKUP_DIR"
for f in "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/RTK.md" \
         "$CODEX_DIR/AGENTS.md" "$CODEX_DIR/hooks.json" "$CODEX_DIR/RTK.md"; do
  if [ -f "$f" ]; then
    run cp "$f" "$BACKUP_DIR/$(basename "$(dirname "$f")")-$(basename "$f")" && [ "$DRY_RUN" -eq 0 ] && ok "$f"
  fi
done

step "바이너리 업데이트"
BIN_FAILED_BEFORE="$FAILED"
if have brew && brew list rtk >/dev/null 2>&1; then
  run brew upgrade rtk || fail "brew upgrade rtk 실패"
elif [ "$(command -v rtk)" = "$HOME/.local/bin/rtk" ]; then
  have curl || die "curl이 필요합니다."
  run_shell "curl -fsSL $RTK_INSTALL_URL | sh" || fail "RTK 설치 스크립트 실패"
else
  fail "$(command -v rtk) 는 이 스크립트가 아는 방식(Homebrew, 공식 설치 스크립트)으로 설치되지 않았습니다. 설치한 방식대로 직접 올리세요 (예: cargo install --git https://github.com/rtk-ai/rtk)."
fi

if [ "$DRY_RUN" -eq 0 ]; then
  NEW="$(rtk_version)"
  if rtk gain >/dev/null 2>&1; then ok "rtk ${NEW:-?}"; else fail "업데이트 후 rtk gain이 실패했습니다."; fi
fi

step "연결 다시 맺기 (새 버전의 지시문 반영)"
if [ "$FAILED" != "$BIN_FAILED_BEFORE" ]; then
  info "바이너리 업데이트가 실패해 연결은 그대로 둡니다."
elif [ "$CLAUDE_HOOK" -eq 1 ]; then
  if [ "$CLAUDE_MD" -eq 1 ]; then
    run rtk init -g --auto-patch </dev/null || fail "rtk init -g --auto-patch 실패"
  else
    run rtk init -g --hook-only --auto-patch </dev/null || fail "rtk init -g --hook-only 실패"
  fi
else
  info "Claude Code: 연결된 적이 없어 건너뜁니다."
fi
if [ "$FAILED" != "$BIN_FAILED_BEFORE" ]; then
  :
elif [ "$CODEX_HOOK" -eq 1 ]; then
  run rtk init -g --codex </dev/null || fail "rtk init -g --codex 실패"
else
  info "Codex: 연결된 적이 없어 건너뜁니다."
fi

step "결과"
if [ -n "$FAILED" ]; then
  err "실패한 단계가 있습니다:$FAILED"
  info "되돌리기: $BACKUP_DIR 의 파일을 원래 위치로 복사하세요."
  exit 1
elif [ "$DRY_RUN" -eq 1 ]; then
  ok "dry-run 완료 (실제로 바꾼 것은 없습니다)"
else
  ok "업데이트 완료. Claude Code와 Codex를 다시 시작하면 반영됩니다."
  info "참고: RTK 1.0부터 rtk proxy <명령> 은 rtk bypass <명령> 입니다 (옛 이름도 동작)."
fi
