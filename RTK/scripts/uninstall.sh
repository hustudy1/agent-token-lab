#!/usr/bin/env bash
#
# RTK 제거 (macOS / Linux)
#   사용법: ./uninstall.sh [옵션]      Windows는 uninstall.ps1
#
# 확인 기준: RTK v0.50.0 · 2026-09-29 · macOS 기본 bash 3.2에서 동작
# 순서: 설치 상태 표시 → Claude Code 연결 해제 → Codex 연결 해제 → 바이너리 삭제 → 제거 확인
#   (바이너리를 먼저 지우면 rtk 명령이 없어 연결 해제를 못 하므로 이 순서를 지킨다)

set -u

SCRIPT_VERSION="2026-09-29"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
BACKUP_ROOT="$HOME/.ai_tokens_backup"

KEEP_BINARY=0
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

run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '    [dry-run] %s\n' "$*"; return 0; fi
  printf '    $ %s\n' "$*"
  "$@"
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
RTK 제거 (macOS / Linux)

  ./uninstall.sh                 연결 해제 + 바이너리 삭제
  ./uninstall.sh --keep-binary   연결만 해제하고 rtk 바이너리는 남김

옵션
  -y, --yes          확인 질문 없이 진행
      --dry-run      실행할 명령만 출력 (아무것도 바꾸지 않음)
      --keep-binary  rtk 바이너리는 지우지 않음
  -h, --help         이 도움말
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-binary) KEEP_BINARY=1 ;;
    --dry-run)     DRY_RUN=1 ;;
    -y|--yes)      ASSUME_YES=1 ;;
    -h|--help)     usage; exit 0 ;;
    *) usage; die "알 수 없는 옵션: $1" ;;
  esac
  shift
done

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) die "지원하지 않는 OS: $(uname -s). Windows에서는 uninstall.ps1을 쓰세요." ;;
esac

# ---------- 설치 흔적 검사 ----------
# scan before : 제거 전에 무엇이 설치돼 있는지 보여준다 (dry-run에서도 실행, 읽기만 함)
# scan after  : 제거 후 남은 것을 경고로 보여준다
# 찾은 개수는 LEFT에 담긴다

LEFT=0
SCAN_MODE=before
found_item() {
  LEFT=$((LEFT + 1))
  if [ "$SCAN_MODE" = "after" ]; then warn "$*"; else info "- $*"; fi
}

# check_file 경로 설명
check_file() { [ -f "$1" ] && found_item "$2: $1"; return 0; }

# check_text 확장정규식 경로 설명 — 파일 안에 패턴이 있으면 해당 줄까지 보여준다
check_text() {
  if [ -f "$2" ] && grep -qiE "$1" "$2" 2>/dev/null; then
    found_item "$3: $2"
    [ "$SCAN_MODE" = "after" ] && grep -niE "$1" "$2" | head -5 | sed 's/^/          /'
  fi
  return 0
}

scan() {
  SCAN_MODE="$1"; LEFT=0
  # Claude Code
  check_text 'rtk hook|rtk-rewrite' "$HOME/.claude/settings.json" "Claude Code 훅"
  check_text '@[^[:space:]]*RTK\.md' "$HOME/.claude/CLAUDE.md"     "Claude Code 참조"
  check_file "$HOME/.claude/RTK.md"                               "Claude Code 파일"
  # Codex (AGENTS.md에는 RTK가 @/절대/경로/RTK.md 형식으로 쓴다)
  check_text 'rtk hook'             "$CODEX_DIR/hooks.json"       "Codex 훅"
  check_text '@[^[:space:]]*RTK\.md' "$CODEX_DIR/AGENTS.md"        "Codex 참조"
  check_file "$CODEX_DIR/RTK.md"                                  "Codex 파일"
  # 바이너리 (after 모드에서 --keep-binary면 남는 게 정상이므로 세지 않음)
  hash -r 2>/dev/null
  if have rtk; then
    if [ "$KEEP_BINARY" -eq 0 ]; then
      found_item "바이너리: $(command -v rtk)"
    elif [ "$1" = "before" ]; then
      info "- 바이너리: $(command -v rtk) (--keep-binary: 남김)"
    fi
  fi
  return 0
}

# ---------- 실행 ----------

printf '%sRTK 제거%s (%s, %s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION" "$OS"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 아무것도 바꾸지 않습니다."
[ "$KEEP_BINARY" -eq 1 ] && info "바이너리는 남깁니다 (--keep-binary)."

step "현재 설치 상태 (제거 대상)"
scan before
if [ "$LEFT" -eq 0 ]; then
  ok "설치된 RTK를 찾지 못했습니다."
else
  info "총 ${LEFT}개"
fi

confirm

step "Claude Code 연결 해제"
if have rtk; then
  run rtk init -g --uninstall || fail "rtk init -g --uninstall 실패"
else
  info "rtk가 없어 건너뜁니다."
fi

step "Codex 연결 해제"
if [ -d "$CODEX_DIR" ]; then
  if have rtk; then
    run rtk init -g --codex --uninstall || fail "rtk init -g --codex --uninstall 실패"
  else
    info "rtk가 없어 건너뜁니다."
  fi
else
  info "$CODEX_DIR 가 없어 건너뜁니다."
fi

if [ "$KEEP_BINARY" -eq 0 ]; then
  step "바이너리 삭제"
  if [ "$OS" = "macos" ] && have brew && brew list rtk >/dev/null 2>&1; then
    run brew uninstall rtk || fail "brew uninstall rtk 실패"
  elif [ -f "$HOME/.local/bin/rtk" ]; then
    run rm -f "$HOME/.local/bin/rtk" || fail "~/.local/bin/rtk 삭제 실패"
  elif have cargo && cargo install --list 2>/dev/null | grep -q '^rtk '; then
    run cargo uninstall rtk || fail "cargo uninstall rtk 실패"
  elif have rtk; then
    warn "rtk가 어떻게 설치됐는지 몰라 지우지 않았습니다: $(command -v rtk)"
  else
    info "rtk 바이너리가 없습니다."
  fi
fi

if [ "$DRY_RUN" -eq 0 ]; then
  step "제거 확인"
  scan after
  if [ "$LEFT" -eq 0 ]; then
    ok "남은 흔적이 없습니다."
  else
    warn "위 ${LEFT}개가 남아 있습니다."
    info "rtk가 v0.50.0 이전이면 Codex 제거를 지원하지 않을 수 있습니다."
    info "남은 줄·파일을 직접 지우거나 설치 전 백업($BACKUP_ROOT)에서 복원하세요."
    FAILED="$FAILED
      - 제거 후 ${LEFT}개 남음"
  fi
fi

step "결과"
if [ -n "$FAILED" ]; then
  err "실패한 단계가 있습니다:$FAILED"
elif [ "$DRY_RUN" -eq 1 ]; then
  ok "dry-run 완료 (실제로 지운 것은 없습니다)"
else
  ok "제거 완료"
fi

cat <<EOF

    참고
      - Claude Code와 Codex를 재시작해야 반영됩니다.
      - 설정이 꼬였다면 백업에서 복원하세요.
          RTK가 만든 백업:   ~/.claude/settings.json.bak
          설치 스크립트 백업: $BACKUP_ROOT
EOF
