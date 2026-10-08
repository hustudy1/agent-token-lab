#!/usr/bin/env bash
#
# Caveman 스킬 설치 (macOS / Linux)
#   사용법: ./install.sh [옵션]        Windows는 install.ps1
#   제거:   ./uninstall.sh
#
# 확인 기준: caveman v2.7.0 · 2026-09-29 · macOS 기본 bash 3.2에서 동작
# 설치하는 것: Caveman 스킬 (MIT)
# 설치하지 않는 것: Caveman 프록시와 CLI (BSL-1.1).
#   프록시는 API 주소를 로컬 프록시로 바꿔서 Claude Code의 MCP tool search를
#   끄는 부작용이 있습니다. ../01_install.md 4단계를 읽고 직접 설치하세요.

set -u

SCRIPT_VERSION="2026-09-29"
NODE_MIN_MAJOR=22
NODE_MIN_MINOR=13
BACKUP_ROOT="$HOME/.ai_tokens_backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-caveman"

DO_CODEX=auto
USE_PLUGIN=0
ALL_SKILLS=0
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
Caveman 스킬 설치 (macOS / Linux)

  ./install.sh              Claude Code(와 Codex)에 Caveman 스킬 설치
  ./uninstall.sh            제거

옵션
  -y, --yes       확인 질문 없이 진행
      --dry-run   실행할 명령만 출력 (아무것도 바꾸지 않음)
      --no-codex  Codex는 건드리지 않음
      --all-skills  스킬 22개 전부 설치 (기본은 caveman, caveman-compress 2개)
      --plugin    Claude Code는 플러그인 방식으로 설치
                  (claude plugin marketplace add + plugin install)
  -h, --help      이 도움말

요구사항
  Node.js 22.13 이상

설치되는 것 (찾은 에이전트만 -a로 지정)
  npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a claude-code -a codex -y -g
  --all-skills면 --skill '*' 로 22개 전부 (매 세션 약 1,000토큰 추가, 추정)
    Claude Code → ~/.claude/skills/    Codex → ~/.agents/skills/
  --plugin이면 Claude Code는 플러그인으로, Codex만 위 명령(-a codex)으로 설치
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-codex) DO_CODEX=no ;;
    --plugin)   USE_PLUGIN=1 ;;
    --all-skills) ALL_SKILLS=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    -y|--yes)   ASSUME_YES=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) usage; die "알 수 없는 옵션: $1" ;;
  esac
  shift
done

case "$(uname -s)" in
  Darwin|Linux) : ;;
  *) die "지원하지 않는 OS: $(uname -s). Windows에서는 install.ps1을 쓰세요." ;;
esac

node_version_ok() {
  have node || return 1
  v="$(node -v 2>/dev/null | sed 's/^v//')"
  major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
  [ "$major" -gt "$NODE_MIN_MAJOR" ] && return 0
  [ "$major" -eq "$NODE_MIN_MAJOR" ] && [ "$minor" -ge "$NODE_MIN_MINOR" ] && return 0
  return 1
}

# Claude Code: CLI가 있거나 ~/.claude 폴더가 있으면 사용 중으로 본다
# (VS Code 확장만 쓰면 claude 명령이 PATH에 없을 수 있다. 설정 폴더는 CLI와 확장이 같이 쓴다)
HAS_CLAUDE=0
if have claude || [ -d "$HOME/.claude" ]; then HAS_CLAUDE=1; fi
HAS_CODEX=0;  have codex  && HAS_CODEX=1
[ "$DO_CODEX" = "no" ] && HAS_CODEX=0

# ---------- 실행 ----------

printf '%sCaveman 스킬 설치%s (%s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 아무것도 바꾸지 않습니다."
info "대상: Claude Code=$([ "$HAS_CLAUDE" -eq 1 ] && echo 있음 || echo 없음), Codex=$([ "$HAS_CODEX" -eq 1 ] && echo 있음 || echo 없음)"
[ "$USE_PLUGIN" -eq 1 ] && info "Claude Code 설치 방식: 플러그인"

if [ "$HAS_CLAUDE" -eq 0 ] && [ "$HAS_CODEX" -eq 0 ]; then
  die "claude도 codex도 찾지 못해 설치할 곳이 없습니다. 에이전트를 먼저 설치하세요."
fi

confirm

step "설정 백업"
info "위치: $BACKUP_DIR"
run mkdir -p "$BACKUP_DIR"
for f in "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md"; do
  if [ -f "$f" ]; then
    run cp "$f" "$BACKUP_DIR/$(basename "$f")" && ok "$f"
  fi
done

step "Node.js 확인"
if node_version_ok; then
  ok "Node.js $(node -v)"
else
  if have node; then
    die "Node.js $NODE_MIN_MAJOR.$NODE_MIN_MINOR 이상이 필요합니다. 현재: $(node -v)"
  else
    die "Node.js $NODE_MIN_MAJOR.$NODE_MIN_MINOR 이상을 먼저 설치하세요."
  fi
fi

step "스킬 설치"
# 설치 대상을 -a로 명시한다. -a가 없으면 skills CLI가 에이전트를 자동으로 찾고,
# 못 찾으면 질문하므로 --yes 실행이 멈출 수 있다.
AGENT_ARGS=""
if [ "$HAS_CLAUDE" -eq 1 ]; then
  if [ "$USE_PLUGIN" -eq 1 ]; then
    have claude || die "--plugin 방식은 claude CLI가 필요합니다. CLI를 설치하거나 --plugin 없이 실행하세요."
    info "Claude Code: 플러그인 방식"
    run claude plugin marketplace add JuliusBrussee/caveman || fail "플러그인 마켓플레이스 추가 실패"
    run claude plugin install caveman@caveman || fail "플러그인 설치 실패"
  else
    AGENT_ARGS="$AGENT_ARGS -a claude-code"
  fi
fi
[ "$HAS_CODEX" -eq 1 ] && AGENT_ARGS="$AGENT_ARGS -a codex"

if [ -n "$AGENT_ARGS" ]; then
  # AGENT_ARGS는 공백 없는 에이전트 이름만 담으므로 따옴표 없이 펼친다
  # shellcheck disable=SC2086
  if [ "$ALL_SKILLS" -eq 1 ]; then
    run npx --yes skills add JuliusBrussee/caveman --skill '*' $AGENT_ARGS -y -g \
      || fail "Caveman 스킬 설치 실패"
  else
    run npx --yes skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress $AGENT_ARGS -y -g \
      || fail "Caveman 스킬 설치 실패"
  fi
fi

step "결과"
if [ -n "$FAILED" ]; then
  err "실패한 단계가 있습니다:$FAILED"
else
  ok "설치 완료"
fi

cat <<EOF

    다음은 직접 확인하세요.
      1. 에이전트를 새 세션으로 시작합니다.
      2. 아무 코딩 질문을 합니다. 서두 없이 짧게 답하면 켜진 것입니다.
      3. 자동으로 켜지지 않으면 /caveman 을 입력합니다.
      4. npx skills ls -g 로 설치된 스킬을 확인합니다 (기본: caveman, caveman-compress).
      5. 며칠 쓴 뒤 npx ccusage@latest claude daily 로 설치 전과 비교합니다.

    모드: /caveman lite | full | ultra   끄기: stop caveman
    제거: ./uninstall.sh
    백업: $BACKUP_DIR
EOF
