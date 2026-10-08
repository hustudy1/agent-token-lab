#!/usr/bin/env bash
#
# Caveman 제거 (macOS / Linux)
#   사용법: ./uninstall.sh [옵션]      Windows는 uninstall.ps1
#
# 확인 기준: caveman v2.7.0 · 2026-09-29 · macOS 기본 bash 3.2에서 동작
# 기본: Caveman 공식 제거 명령으로 스킬 등 설치한 것을 되돌립니다.
# --with-proxy: 직접 설치한 프록시 연결과 CLI(@caveman-ai/cli)까지 제거합니다.

set -u

SCRIPT_VERSION="2026-09-29"
BACKUP_ROOT="$HOME/.ai_tokens_backup"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"

# --skill '*'로 설치되는 Caveman 스킬 22개 (2026-10-07 실제 설치로 확인, v2.7.0)
# 이름에 cave가 들어간 폴더는 이 목록에 없어도 함께 찾는다 (스킬이 늘어날 때 대비)
SKILL_NAMES="caveman cavecrew caveman-commit caveman-compress caveman-discover
  caveman-evidence-review caveman-explore caveman-help caveman-learn caveman-manage
  caveman-optimize caveman-review caveman-setup caveman-stats investigate-first
  lean-build megacave migration safe-refactor surgical-patch ultracave verify-and-stop"

# 에이전트별 전역 스킬 폴더
#   Claude Code: ~/.claude/skills
#   Codex: skills CLI는 ~/.agents/skills 에 설치한다 (2026-10-07 실제 확인). ~/.codex/skills 도 함께 본다
CLAUDE_SKILL_DIRS="$HOME/.claude/skills"
CODEX_SKILL_DIRS="$HOME/.agents/skills $CODEX_DIR/skills"
SKILL_DIRS="$CLAUDE_SKILL_DIRS $CODEX_SKILL_DIRS $HOME/.config/agents/skills"

# caveman_names_in 폴더...: 폴더들에 있는 Caveman 스킬 이름을 중복 없이 출력
caveman_names_in() {
  out=" "
  for dir in "$@"; do
    [ -d "$dir" ] || continue
    for n in $SKILL_NAMES; do
      if [ -e "$dir/$n" ] || [ -L "$dir/$n" ]; then
        case "$out" in *" $n "*) ;; *) out="$out$n " ;; esac
      fi
    done
    for p in "$dir"/*cave*; do
      [ -e "$p" ] || [ -L "$p" ] || continue
      n="$(basename "$p")"
      case "$out" in *" $n "*) ;; *) out="$out$n " ;; esac
    done
  done
  echo $out
}

WITH_PROXY=0
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
Caveman 제거 (macOS / Linux)

  ./uninstall.sh                Caveman 스킬 등 설치한 것 제거
  ./uninstall.sh --with-proxy   프록시 연결과 CLI까지 제거

옵션
  -y, --yes         확인 질문 없이 진행
      --dry-run     실행할 명령만 출력 (아무것도 바꾸지 않음)
      --with-proxy  caveman disable claude/codex + npm uninstall -g @caveman-ai/cli
  -h, --help        이 도움말
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with-proxy) WITH_PROXY=1 ;;
    --dry-run)    DRY_RUN=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) usage; die "알 수 없는 옵션: $1" ;;
  esac
  shift
done

case "$(uname -s)" in
  Darwin|Linux) : ;;
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

scan() {
  SCAN_MODE="$1"; LEFT=0
  for base in $SKILL_DIRS; do
    for n in $(caveman_names_in "$base"); do found_item "스킬: $base/$n"; done
  done
  if [ -d "$HOME/.claude/plugins" ]; then
    plugins="$(find "$HOME/.claude/plugins" -maxdepth 4 -iname '*caveman*' 2>/dev/null | head -10)"
    if [ -n "$plugins" ]; then
      old_ifs=$IFS; IFS='
'
      for p in $plugins; do found_item "플러그인: $p"; done
      IFS=$old_ifs
    fi
  fi
  if [ -f "$HOME/.claude/settings.json" ] && grep -qi 'caveman' "$HOME/.claude/settings.json"; then
    found_item "설정: ~/.claude/settings.json 에 caveman 항목 (훅·상태줄)"
  fi
  hash -r 2>/dev/null
  have caveman && found_item "CLI: $(command -v caveman)"
  return 0
}

# ---------- 실행 ----------

printf '%sCaveman 제거%s (%s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 아무것도 바꾸지 않습니다."
[ "$WITH_PROXY" -eq 1 ] && info "프록시 연결과 CLI까지 제거합니다."

step "현재 설치 상태 (제거 대상)"
scan before
if [ "$LEFT" -eq 0 ]; then
  ok "설치된 Caveman을 찾지 못했습니다."
else
  info "총 ${LEFT}개"
fi

confirm

if [ "$WITH_PROXY" -eq 1 ]; then
  step "프록시 연결 해제와 CLI 제거"
  if have caveman; then
    for agent in claude codex; do
      run caveman disable "$agent" || warn "caveman disable $agent 실패 (연결된 적이 없으면 정상)"
    done
  else
    info "caveman CLI가 없어 프록시 연결 해제는 건너뜁니다."
  fi
  if have npm; then
    run npm uninstall -g @caveman-ai/cli || fail "npm uninstall -g @caveman-ai/cli 실패"
  else
    warn "npm이 없어 CLI 제거를 건너뜁니다."
  fi
elif have caveman; then
  warn "caveman CLI(프록시)가 설치되어 있습니다. 함께 지우려면 --with-proxy 로 다시 실행하세요."
fi

step "스킬 제거 (skills CLI)"
# Caveman 공식 제거 명령은 npx skills로 설치한 스킬을 지우지 않는다 (2026-10-07 실제 실행으로 확인).
# 그래서 에이전트별 스킬 폴더에 있는 Caveman 스킬만 골라 skills CLI로 지운다.
remove_skills_for() {   # $1: 에이전트 이름(-a 값)  $2...: 스킬 폴더
  agent="$1"; shift
  # shellcheck disable=SC2068
  names="$(caveman_names_in $@)"
  if [ -z "$names" ]; then
    info "$agent: 지울 Caveman 스킬 없음"
    return 0
  fi
  # names는 공백 없는 스킬 이름만 담으므로 따옴표 없이 펼친다
  # shellcheck disable=SC2086
  run npx --yes skills remove -g -a "$agent" -y $names || fail "$agent 스킬 제거 실패"
}
if have npx; then
  # shellcheck disable=SC2086
  remove_skills_for claude-code $CLAUDE_SKILL_DIRS
  # shellcheck disable=SC2086
  remove_skills_for codex $CODEX_SKILL_DIRS
else
  fail "npx가 없어 스킬을 지울 수 없습니다. Node.js를 설치한 뒤 다시 실행하세요."
fi

step "나머지 제거 (Caveman 공식 제거 명령: 훅, 플러그인, MCP)"
if have npx; then
  run npx -y github:JuliusBrussee/caveman -- --uninstall || fail "Caveman 제거 실패"
else
  fail "npx가 없어 제거할 수 없습니다. Node.js를 설치한 뒤 다시 실행하세요."
fi

if [ "$DRY_RUN" -eq 0 ]; then
  step "제거 확인"
  scan after
  if [ "$LEFT" -eq 0 ]; then
    ok "남은 흔적이 없습니다."
  else
    warn "위 ${LEFT}개가 남아 있습니다. 직접 지우거나 설치 전 백업($BACKUP_ROOT)에서 복원하세요."
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
      - Claude Code 플러그인 방식(--plugin)으로 설치했다면
        Claude Code의 /plugin 메뉴에서도 caveman이 지워졌는지 확인하세요.
      - 에이전트를 새 세션으로 시작해야 반영됩니다.
      - 설치 전 백업: $BACKUP_ROOT
EOF
