#!/usr/bin/env bash
#
# Caveman 업데이트 (macOS / Linux)
#   사용법: ./update.sh [옵션]         Windows는 update.ps1
#
# 확인 기준: caveman v4.0.1 · skills CLI 1.7.4 · 2026-10-22 · macOS 기본 bash 3.2에서 동작
# 설치되어 있는 것만 최신으로 올린다. 새로 설치하지 않는다.
#   스킬(npx skills)    → npx skills update <설치된 스킬> -g -y
#   Claude Code 플러그인 → claude plugin update caveman@caveman
#   CLI·프록시(npm -g)  → npm install -g @caveman-ai/cli@latest

set -u

# Caveman CLI(3.0.0부터)와 일부 하위 도구는 사용 통계를 기본으로 보낸다. 이 스크립트가 부르는 명령은 모두 끈다.
export DO_NOT_TRACK=1

SCRIPT_VERSION="2026-10-22"
DRY_RUN=0
ASSUME_YES=0
FAILED=""

SKILL_NAMES="caveman cavecrew caveman-commit caveman-compress caveman-discover
  caveman-evidence-review caveman-explore caveman-help caveman-learn caveman-manage
  caveman-optimize caveman-review caveman-setup caveman-stats investigate-first
  lean-build megacave migration safe-refactor surgical-patch ultracave verify-and-stop"
SKILL_DIRS="$HOME/.claude/skills $HOME/.agents/skills ${CODEX_HOME:-$HOME/.codex}/skills"

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
Caveman 업데이트 (macOS / Linux)

  ./update.sh               설치된 Caveman을 최신으로 올림 (새로 설치하지 않음)

옵션
  -y, --yes       확인 질문 없이 진행
      --dry-run   실행할 명령만 출력 (아무것도 바꾸지 않음)
  -h, --help      이 도움말

올리는 것 (설치되어 있는 것만)
  스킬                 npx skills update <설치된 스킬> -g -y
  Claude Code 플러그인  claude plugin update caveman@caveman
  CLI·프록시           npm install -g @caveman-ai/cli@latest
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
  Darwin|Linux) : ;;
  *) die "지원하지 않는 OS: $(uname -s). Windows에서는 update.ps1을 쓰세요." ;;
esac

# 설치된 Caveman 스킬 이름 (중복 없이)
installed_skills() {
  for d in $SKILL_DIRS; do
    [ -d "$d" ] || continue
    for n in $SKILL_NAMES; do [ -d "$d/$n" ] && echo "$n"; done
    (cd "$d" && ls -d *cave* 2>/dev/null)
  done | sort -u | tr '\n' ' '
}

# 스킬 내용의 지문. 업데이트 전후를 비교해 바뀌었는지 알려 준다
skill_fingerprint() {
  for d in $SKILL_DIRS; do
    [ -f "$d/caveman/SKILL.md" ] && cksum < "$d/caveman/SKILL.md"
  done | sort -u | tr '\n' ' '
}

HAS_PLUGIN=0
have claude && claude plugin list 2>/dev/null | grep -q 'caveman@caveman' && HAS_PLUGIN=1
HAS_CLI=0
have npm && npm ls -g @caveman-ai/cli --depth=0 >/dev/null 2>&1 && HAS_CLI=1

# ---------- 실행 ----------

printf '%sCaveman 업데이트%s (%s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 아무것도 바꾸지 않습니다."

SKILLS="$(installed_skills)"
info "스킬: ${SKILLS:-없음}"
info "Claude Code 플러그인: $([ "$HAS_PLUGIN" -eq 1 ] && echo 있음 || echo 없음)"
info "CLI(@caveman-ai/cli): $([ "$HAS_CLI" -eq 1 ] && echo "있음 $(npm ls -g @caveman-ai/cli --depth=0 2>/dev/null | grep -o 'cli@[0-9.]*')" || echo 없음)"

if [ -z "$SKILLS" ] && [ "$HAS_PLUGIN" -eq 0 ] && [ "$HAS_CLI" -eq 0 ]; then
  ok "설치된 Caveman이 없어 올릴 것이 없습니다. 설치는 ./install.sh"
  exit 0
fi

confirm

BEFORE="$(skill_fingerprint)"

if [ -n "$SKILLS" ]; then
  step "스킬 업데이트 (skills CLI)"
  if have npx; then
    # SKILLS는 공백 없는 스킬 이름만 담으므로 따옴표 없이 펼친다
    # shellcheck disable=SC2086
    run npx --yes skills update $SKILLS -g -y </dev/null || fail "스킬 업데이트 실패"
  else
    fail "npx가 없어 스킬을 올릴 수 없습니다. Node.js를 설치하세요."
  fi
fi

if [ "$HAS_PLUGIN" -eq 1 ]; then
  step "Claude Code 플러그인 업데이트"
  run claude plugin update caveman@caveman || fail "플러그인 업데이트 실패"
fi

if [ "$HAS_CLI" -eq 1 ]; then
  step "CLI·프록시 업데이트"
  run npm install -g @caveman-ai/cli@latest || fail "CLI 업데이트 실패"
  warn "Caveman CLI는 사용 통계를 기본으로 보냅니다. 끄기: caveman telemetry off (또는 DO_NOT_TRACK=1)"
fi

step "결과"
if [ "$DRY_RUN" -eq 0 ] && [ -n "$SKILLS" ]; then
  if [ "$(skill_fingerprint)" = "$BEFORE" ]; then info "caveman 스킬 내용: 이미 최신 (바뀐 것 없음)"
  else ok "caveman 스킬 내용: 새 버전으로 바뀜"; fi
fi
if [ -n "$FAILED" ]; then
  err "실패한 단계가 있습니다:$FAILED"
  exit 1
elif [ "$DRY_RUN" -eq 1 ]; then
  ok "dry-run 완료 (실제로 바꾼 것은 없습니다)"
else
  ok "업데이트 완료. 에이전트를 새 세션으로 시작하면 반영됩니다."
fi
