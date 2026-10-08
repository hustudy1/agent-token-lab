#!/usr/bin/env bash
#
# RTK 설치 (macOS / Linux)
#   사용법: ./install.sh [옵션]        Windows는 install.ps1
#   제거:   ./uninstall.sh
#
# 확인 기준: RTK v0.50.0 · 2026-09-29 · macOS 기본 bash 3.2에서 동작
# 설치 방식: macOS는 Homebrew(없으면 공식 설치 스크립트), Linux는 공식 설치 스크립트
# 연결: Claude Code와 Codex 모두 PreToolUse 훅 (Codex 훅은 v0.50.0부터)

set -u

SCRIPT_VERSION="2026-09-29"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_HOOK_MIN="0.50.0"
BACKUP_ROOT="$HOME/.ai_tokens_backup"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-rtk"
RTK_INSTALL_URL="https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh"

DO_CODEX=auto
HOOK_ONLY=0
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

# "rtk 0.50.0" 같은 출력에서 버전 숫자만 꺼낸다
rtk_version() { rtk --version 2>/dev/null | sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1; }

# version_ge A B: A >= B 이면 참 (x.y.z 숫자 비교)
version_ge() {
  [ -n "$1" ] || return 1
  a1="$(echo "$1" | cut -d. -f1)"; a2="$(echo "$1" | cut -d. -f2)"; a3="$(echo "$1" | cut -d. -f3)"
  b1="$(echo "$2" | cut -d. -f1)"; b2="$(echo "$2" | cut -d. -f2)"; b3="$(echo "$2" | cut -d. -f3)"
  [ "$a1" -gt "$b1" ] && return 0; [ "$a1" -lt "$b1" ] && return 1
  [ "$a2" -gt "$b2" ] && return 0; [ "$a2" -lt "$b2" ] && return 1
  [ "$a3" -ge "$b3" ]
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then printf '    [dry-run] %s\n' "$*"; return 0; fi
  printf '    $ %s\n' "$*"
  "$@"
}

# 파이프가 들어간 명령은 sh -c로 실행한다
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
RTK 설치 (macOS / Linux)

  ./install.sh               RTK 설치 + Claude Code(와 Codex) 연결
  ./uninstall.sh             제거

옵션
  -y, --yes        확인 질문 없이 진행
      --dry-run    실행할 명령만 출력 (아무것도 바꾸지 않음)
      --no-codex   Codex는 건드리지 않음
      --hook-only  Claude Code에 훅만 등록 (~/.claude/CLAUDE.md에 @RTK.md를 넣지 않음)
  -h, --help       이 도움말

바꾸는 파일
  ~/.claude/settings.json   PreToolUse 훅 등록 (RTK가 .bak 백업을 만듦)
  ~/.claude/CLAUDE.md       @RTK.md 한 줄 추가 (--hook-only면 안 함)
  ~/.claude/RTK.md          10줄 파일 생성 (--hook-only면 안 함)
  ~/.codex/hooks.json       Codex PreToolUse 훅 등록 (Codex가 있을 때)
  ~/.codex/AGENTS.md        @RTK.md 한 줄 추가 (Codex가 있을 때)
  ~/.codex/RTK.md           RTK가 만드는 파일 (Codex가 있을 때)
                            ($CODEX_HOME이 있으면 그 폴더)

  바꾸기 전에 ~/.ai_tokens_backup/<타임스탬프>-rtk/ 로 백업합니다.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-codex)  DO_CODEX=no ;;
    --hook-only) HOOK_ONLY=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    -y|--yes)    ASSUME_YES=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) usage; die "알 수 없는 옵션: $1" ;;
  esac
  shift
done

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *) die "지원하지 않는 OS: $(uname -s). Windows에서는 install.ps1을 쓰세요." ;;
esac

# Claude Code: CLI가 있거나 ~/.claude 폴더가 있으면 사용 중으로 본다
# (VS Code 확장만 쓰면 claude 명령이 PATH에 없을 수 있다. 설정 폴더는 CLI와 확장이 같이 쓴다)
HAS_CLAUDE=0
if have claude || [ -d "$HOME/.claude" ]; then HAS_CLAUDE=1; fi
HAS_CODEX=0;  have codex  && HAS_CODEX=1
[ "$DO_CODEX" = "no" ] && HAS_CODEX=0

# ---------- 실행 ----------

printf '%sRTK 설치%s (%s, %s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION" "$OS"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 아무것도 바꾸지 않습니다."
info "대상: Claude Code=$([ "$HAS_CLAUDE" -eq 1 ] && echo 있음 || echo 없음), Codex=$([ "$HAS_CODEX" -eq 1 ] && echo 있음 || echo 없음)"
[ "$HOOK_ONLY" -eq 1 ] && info "Claude Code: 훅만 등록 (--hook-only)"

if [ "$HAS_CLAUDE" -eq 0 ] && [ "$HAS_CODEX" -eq 0 ]; then
  warn "claude도 codex도 찾지 못했습니다. 바이너리만 설치하고 연결은 건너뜁니다."
fi

confirm

step "설정 백업"
info "위치: $BACKUP_DIR"
run mkdir -p "$BACKUP_DIR"
for f in "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" \
         "$CODEX_DIR/AGENTS.md" "$CODEX_DIR/hooks.json" "$CODEX_DIR/config.toml"; do
  if [ -f "$f" ]; then
    run cp "$f" "$BACKUP_DIR/$(basename "$f")" && ok "$f"
  fi
done

step "바이너리 설치"
if have rtk; then
  ok "이미 설치됨: $(rtk --version 2>/dev/null || echo '버전 확인 실패')"
elif [ "$OS" = "macos" ] && have brew; then
  run brew install rtk || die "brew install rtk 실패"
else
  info "공식 설치 스크립트로 설치합니다 (~/.local/bin)."
  have curl || die "curl이 필요합니다."
  run_shell "curl -fsSL $RTK_INSTALL_URL | sh" || die "RTK 설치 스크립트 실패"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *)
      warn "PATH에 ~/.local/bin이 없습니다. 셸 설정에 아래 줄을 추가하고 새 터미널을 여세요."
      info '  export PATH="$HOME/.local/bin:$PATH"'
      PATH="$HOME/.local/bin:$PATH"   # 이 스크립트 안에서만 적용
      ;;
  esac
fi

step "설치 확인"
if [ "$DRY_RUN" -eq 1 ]; then
  info "[dry-run] rtk --version && rtk gain"
else
  have rtk || die "rtk 명령을 찾을 수 없습니다. PATH를 확인하세요."
  # crates.io의 다른 'rtk'(Rust Type Kit)가 설치된 경우를 걸러낸다
  if ! rtk gain >/dev/null 2>&1; then
    die "rtk gain이 실패했습니다. 다른 프로젝트의 rtk일 수 있습니다(crates.io의 Rust Type Kit). cargo install --git https://github.com/rtk-ai/rtk 로 다시 설치하세요."
  fi
  ok "$(rtk --version 2>/dev/null)"
fi
have rg || warn "ripgrep(rg)이 없으면 일부 필터가 경고를 냅니다. 설치 권장: brew install ripgrep / apt install ripgrep"

if [ "$HAS_CLAUDE" -eq 1 ]; then
  step "Claude Code 연결"
  if [ "$HOOK_ONLY" -eq 1 ]; then
    # --hook-only와 --auto-patch를 함께 쓰는 조합은 README에 없어서, 실패하면 질문 방식으로 다시 시도한다
    run rtk init -g --hook-only --auto-patch \
      || run rtk init -g --hook-only \
      || fail "rtk init -g --hook-only 실패"
  else
    run rtk init -g --auto-patch || fail "rtk init -g --auto-patch 실패"
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    rtk init --show || warn "rtk init --show 결과를 확인하세요."
  fi
else
  warn "claude 명령이 없어 Claude Code 연결은 건너뜁니다."
fi

if [ "$HAS_CODEX" -eq 1 ]; then
  step "Codex 연결"
  if [ "$DRY_RUN" -eq 0 ] && ! version_ge "$(rtk_version)" "$CODEX_HOOK_MIN"; then
    warn "rtk $(rtk_version)은 Codex 훅을 지원하지 않습니다 (v$CODEX_HOOK_MIN부터)."
    warn "이 버전은 AGENTS.md 지시문만 넣습니다. 업데이트 권장: brew upgrade rtk (또는 설치 스크립트 재실행)"
  fi
  info "$CODEX_DIR 에 hooks.json 훅, AGENTS.md(@RTK.md), RTK.md를 씁니다."
  run rtk init -g --codex || fail "rtk init -g --codex 실패"
fi

CODEX_NOTE=""
if [ "$HAS_CODEX" -eq 1 ]; then
  CODEX_NOTE="      - Codex를 재시작합니다. 훅 신뢰 확인이 나오면 승인하세요 (/hooks 에서도 확인 가능).
        Codex에서 git status 실행을 요청 → rtk git status로 바뀌는지 확인합니다.
"
fi

step "결과"
if [ -n "$FAILED" ]; then
  err "실패한 단계가 있습니다:$FAILED"
else
  ok "설치 완료"
fi

cat <<EOF

    다음은 직접 확인하세요.
      - Claude Code를 재시작합니다 (훅과 CLAUDE.md는 새 세션부터 적용).
      - Claude Code에서 git status 실행을 요청 → rtk git status로 바뀌는지 확인합니다.
$CODEX_NOTE      - 며칠 쓴 뒤 npx ccusage@latest claude daily 로 설치 전과 비교합니다.

    주의: rtk gain 수치는 RTK의 자체 추정이지 청구액이 아닙니다.
    제거: ./uninstall.sh
    백업: $BACKUP_DIR
EOF
