#!/usr/bin/env bash
#
# agent-token-lab 설정 (macOS / Linux)
#
#   bash setup.sh                 메뉴에서 고르기
#   bash setup.sh <명령> [-y]     메뉴 없이 바로 실행 (에이전트·자동화용)
#
# 명령: caveman | rtk | all | status | remove-caveman | remove-rtk | remove-all
#       usage | sessions | context [프로젝트 폴더] | gain | results
# 설치·제거 로직은 Caveman/scripts, RTK/scripts 의 스크립트에 있고, 이 파일은 그것을 불러 쓴다.
# 실행 순서: 계획 보여주기(dry-run) → 확인 → 실행. -y 를 주면 확인 없이 진행한다.

set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSUME_YES=0
CMD=""
PROJECT=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_B="$(printf '\033[1m')"; C_R="$(printf '\033[31m')"; C_G="$(printf '\033[32m')"
  C_Y="$(printf '\033[33m')"; C_0="$(printf '\033[0m')"
else
  C_B=""; C_R=""; C_G=""; C_Y=""; C_0=""
fi

title() { printf '\n%s%s%s\n' "$C_B" "$*" "$C_0"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  %s[OK]%s %s\n' "$C_G" "$C_0" "$*"; }
warn()  { printf '  %s[주의]%s %s\n' "$C_Y" "$C_0" "$*"; }
die()   { printf '\n%s[중단]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
agent-token-lab 설정

  bash setup.sh                메뉴에서 고르기
  bash setup.sh <명령> [-y]    메뉴 없이 바로 실행 (-y: 확인 질문 없이 진행)

명령
  caveman          Caveman 스킬 설치 (추천)
  rtk              RTK 설치
  all              둘 다 설치
  status           설치 상태 확인
  remove-caveman   Caveman 제거
  remove-rtk       RTK 제거
  remove-all       둘 다 제거

사용량·절약 보기
  usage            일별 사용량과 사용량 구성 (최근 30일, ccusage)
  sessions         사용량이 큰 대화(세션) 상위 10개
  context [폴더]   매 세션 항상 실리는 것 점검 (CLAUDE.md·AGENTS.md·스킬·MCP)
  gain             RTK 자체 추정 절약량 (청구액 아님)
  results          이 저장소의 자체 측정 결과 요약
EOF
}

for a in "$@"; do
  case "$a" in
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    caveman|rtk|all|status|remove-caveman|remove-rtk|remove-all) CMD="$a" ;;
    usage|sessions|context|gain|results) CMD="$a" ;;
    *)
      # context 다음에 오는 값은 점검할 프로젝트 폴더
      if [ "$CMD" = "context" ] && [ -z "$PROJECT" ]; then PROJECT="$a"
      else usage; die "알 수 없는 명령: $a"; fi
      ;;
  esac
done

case "$(uname -s)" in
  Darwin|Linux) : ;;
  *) die "Windows에서는 setup.bat 을 실행하세요." ;;
esac

# ---------- 상태 확인 ----------

show_status() {
  title "설치 상태"
  found=""
  for d in "$HOME/.claude/skills" "$HOME/.agents/skills" "${CODEX_HOME:-$HOME/.codex}/skills"; do
    [ -d "$d" ] || continue
    names="$(cd "$d" && ls -d *cave* 2>/dev/null | tr '\n' ' ')"
    [ -n "$names" ] && found="$found
    $d: $names"
  done
  if [ -n "$found" ]; then ok "Caveman 스킬:$found"; else info "Caveman: 설치 안 됨"; fi

  if have rtk; then
    ok "RTK: $(rtk --version 2>/dev/null) ($(command -v rtk))"
    if grep -q 'rtk hook' "$HOME/.claude/settings.json" 2>/dev/null; then ok "RTK Claude Code 훅: 연결됨"; else warn "RTK Claude Code 훅: 연결 안 됨"; fi
    if grep -q 'rtk hook' "${CODEX_HOME:-$HOME/.codex}/hooks.json" 2>/dev/null; then ok "RTK Codex 훅: 연결됨"; fi
  else
    info "RTK: 설치 안 됨"
  fi

  have claude && info "Claude Code: $(claude --version 2>/dev/null | head -1)"
  [ -d "$HOME/.claude" ] && ! have claude && info "Claude Code: VS Code 확장 등 (~/.claude 있음)"
  have codex && info "Codex: $(codex --version 2>/dev/null | head -1)"
  return 0
}

# ---------- 사용량·절약 ----------
# 표 정리와 점검 로직은 tools/usage_report.py 에 있다

CCU="npx --yes ccusage@latest"
REPORT="$ROOT/tools/usage_report.py"

# N일 전 날짜 (YYYYMMDD). macOS(date -v)와 Linux(date -d) 모두 지원
since_days() { date -v-"$1"d +%Y%m%d 2>/dev/null || date -d "$1 days ago" +%Y%m%d 2>/dev/null; }

need() {   # need npx|python3
  case "$1" in
    npx)     have npx     || { warn "npx가 없어 사용량을 볼 수 없습니다. Node.js를 설치하세요."; return 1; } ;;
    python3) have python3 || { warn "python3가 없어 결과를 정리할 수 없습니다."; return 1; } ;;
  esac
  return 0
}

show_daily() {
  title "일별 사용량 (최근 30일)"
  need npx || return 0
  info "ccusage가 이 컴퓨터의 Claude Code 기록(로컬 파일)을 읽습니다. 처음에는 내려받느라 시간이 걸립니다."
  $CCU claude daily --since "$(since_days 30)" </dev/null
  if have codex; then
    title "Codex 일별 사용량 (최근 30일)"
    $CCU codex daily --since "$(since_days 30)" </dev/null
  fi
  info "Cost는 API 단가로 환산한 값입니다. 구독이면 실제로는 사용 한도에서 차감됩니다."
}

show_mix() {
  title "사용량 구성 (최근 30일)"
  need npx && need python3 || return 0
  $CCU claude daily --since "$(since_days 30)" --json </dev/null 2>/dev/null | python3 "$REPORT" mix
}

show_sessions() {
  title "사용량이 큰 대화(세션) 상위 10개 (최근 30일)"
  need npx && need python3 || return 0
  $CCU claude session --since "$(since_days 30)" --json </dev/null 2>/dev/null | python3 "$REPORT" sessions
}

show_context() {
  title "상시 로딩 점검 (매 세션 항상 실리는 것)"
  need python3 || return 0
  python3 "$REPORT" context "${1:-}"
}

show_gain() {
  title "RTK 자체 추정 절약량"
  if ! have rtk; then info "RTK가 설치되어 있지 않습니다."; return 0; fi
  rtk gain </dev/null 2>&1 | sed -n '1,12p'
  warn "RTK가 스스로 추정한 값입니다. 청구액이 아닙니다."
  info "글자수÷4로 토큰을 추정하고, 잘리기 전 원본 전체를 기준으로 계산하며, 캐시 재읽기는 보지 못합니다."
  info "실제 효과는 메뉴의 '자체 측정 결과'를 보세요 (RTK: 효과 없음)."
}

show_results() {
  title "자체 측정 결과 (2026-10-08, sonnet, 5회 평균)"
  cat <<'EOF'
  | 도구     | 출력 토큰 | 실제 효과 (캐시 영향을 뺀 비용) |
  |----------|-----------|----------------------------------|
  | Caveman  | -30%      | 약 -7%                           |
  | RTK      | 변화 없음 | +4% (효과 없음)                  |

  - Caveman: 출력은 크게 줄지만 비용의 대부분이 컨텍스트라 전체 효과는 한 자릿수입니다.
  - RTK: 에이전트가 옵션·| head 를 붙여 실행해 RTK가 줄일 출력이 없었습니다.
  - 더 큰 절약: 대화를 짧게 끊기(/clear), 상시 로딩 줄이기 (메뉴의 '상시 로딩 점검').
  자세한 내용: test/01_measure.md  · 직접 재기: bash test/ab_test.sh --help
EOF
}

# ---------- 실행: 계획 → 확인 → 실행 ----------

ask() {   # ask "질문" → 예면 0
  [ "$ASSUME_YES" -eq 1 ] && return 0
  printf '\n%s [y/N] ' "$1"
  read -r answer || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

run_step() {   # run_step <Caveman|RTK> <install|uninstall>
  tool="$1"; action="$2"; script="$ROOT/$tool/scripts/$action.sh"
  [ -f "$script" ] || die "스크립트가 없습니다: $script"
  if [ "$action" = "install" ]; then label="$tool 설치"; else label="$tool 삭제"; fi
  title "[$label] 계획 (아직 아무것도 바꾸지 않습니다)"
  # 하위 스크립트는 --yes 로 돌아 입력이 필요 없다. 표준 입력을 막아 두지 않으면
  # npx 같은 하위 명령이 사용자가 다음 질문에 답할 입력까지 읽어 간다 (2026-10-13 검증에서 확인)
  bash "$script" --dry-run --yes </dev/null || { warn "$label 계획 단계에서 멈췄습니다. 위 메시지를 확인하세요."; return 1; }
  if ! ask "위 계획대로 진행할까요? ($label)"; then
    info "$label: 건너뜁니다."
    return 0
  fi
  title "[$label] 실행"
  bash "$script" --yes </dev/null
}

run_cmd() {
  case "$1" in
    caveman)        run_step Caveman install ;;
    rtk)            run_step RTK install ;;
    all)            run_step Caveman install; run_step RTK install ;;
    status)         show_status ;;
    remove-caveman) run_step Caveman uninstall ;;
    remove-rtk)     run_step RTK uninstall ;;
    remove-all)     run_step Caveman uninstall; run_step RTK uninstall ;;
    usage)          show_daily; show_mix ;;
    sessions)       show_sessions ;;
    context)        show_context "$PROJECT" ;;
    gain)           show_gain ;;
    results)        show_results ;;
  esac
}

if [ -n "$CMD" ]; then
  run_cmd "$CMD"
  exit $?
fi

# ---------- 메뉴 ----------
# 1단계: 작업(설치/삭제/상태) → 2단계: 서비스(Caveman/RTK/둘 다) → 계획 → 확인 → 실행 → 처음 메뉴

# SETUP_FORCE_MENU=1 은 입력을 파이프로 넣어 메뉴를 시험할 때만 쓴다
if [ ! -t 0 ] && [ "${SETUP_FORCE_MENU:-0}" != "1" ]; then
  die "메뉴는 터미널에서만 쓸 수 있습니다. 명령을 직접 주세요: bash setup.sh caveman -y"
fi

cave_state() {
  for d in "$HOME/.claude/skills" "$HOME/.agents/skills" "${CODEX_HOME:-$HOME/.codex}/skills"; do
    if ls -d "$d"/*cave* >/dev/null 2>&1; then echo "설치됨"; return; fi
  done
  echo "없음"
}
rtk_state() {
  if have rtk; then echo "설치됨 $(rtk --version 2>/dev/null | awk '{print $2}')"; else echo "없음"; fi
}

# read_choice "허용 번호들" → CHOICE. 잘못 넣으면 다시 묻는다
read_choice() {
  while :; do
    printf '\n  선택: '
    read -r CHOICE || { CHOICE=0; return; }
    case " $1 " in *" $CHOICE "*) return ;; esac
    warn "목록에 있는 번호를 입력하세요 ($1)"
  done
}

line() { printf '%s\n' "  ------------------------------------------------------------"; }

# menu_usage → 사용량·절약 보기. 뒤로 가면 1 반환
menu_usage() {
  title "  사용량·절약 보기"
  line
  printf '  1) 일별 사용량            최근 30일 (Claude Code, Codex 있으면 Codex도)\n'
  printf '  2) 사용량이 큰 대화 10개   비싼 대화 찾기\n'
  printf '  3) 사용량 구성            캐시 읽기·쓰기·출력이 각각 비용의 몇 %%인지\n'
  printf '  4) 상시 로딩 점검         CLAUDE.md·AGENTS.md·스킬·MCP 서버\n'
  printf '  5) RTK 자체 추정 절약량    rtk gain (청구액 아님)\n'
  printf '  6) 자체 측정 결과          Caveman 약 -7%%, RTK 효과 없음\n'
  printf '  9) 뒤로\n'
  line
  read_choice "1 2 3 4 5 6 9"
  case "$CHOICE" in
    1) show_daily ;;
    2) show_sessions ;;
    3) show_mix ;;
    4) printf '\n  함께 점검할 프로젝트 폴더 경로 (엔터: 전역 설정만): '
       read -r proj_path || proj_path=""
       show_context "$proj_path" ;;
    5) show_gain ;;
    6) show_results ;;
    9) return 1 ;;
  esac
  return 0
}

# menu_service install|uninstall → 고른 서비스 실행. 뒤로 가면 1 반환
menu_service() {
  action="$1"
  if [ "$action" = "install" ]; then verb="설치"; else verb="삭제"; fi
  title "  ${verb}할 서비스를 고르세요"
  line
  printf '  1) Caveman   답변을 짧게 해 출력 토큰 절약 · 자체 측정: 비용 약 -7%%    [현재: %s]\n' "$(cave_state)"
  printf '  2) RTK       셸 명령 출력 압축 · 자체 측정: 효과 없음                [현재: %s]\n' "$(rtk_state)"
  printf '  3) 둘 다\n'
  printf '  9) 뒤로\n'
  line
  read_choice "1 2 3 9"
  case "$CHOICE" in
    1) run_step Caveman "$action" ;;
    2) run_step RTK "$action" ;;
    3) run_step Caveman "$action"; run_step RTK "$action" ;;
    9) return 1 ;;
  esac
  return 0
}

while :; do
  title "=============================================================="
  title "  Caveman · RTK 구성 작업 (agent-token-lab)"
  title "=============================================================="
  info "현재 상태 — Caveman: $(cave_state) · RTK: $(rtk_state)"
  title "  원하는 작업을 고르세요"
  line
  printf '  1) 설치\n'
  printf '  2) 삭제\n'
  printf '  3) 설치 상태 자세히 보기\n'
  printf '  4) 사용량·절약 보기\n'
  printf '  0) 끝내기\n'
  line
  read_choice "1 2 3 4 0"
  case "$CHOICE" in
    1) menu_service install   || continue ;;
    2) menu_service uninstall || continue ;;
    3) show_status ;;
    4) menu_usage             || continue ;;
    0) info "끝냅니다."; exit 0 ;;
  esac
  printf '\n  처음 메뉴로 돌아갈까요? [Y/n] '
  read -r again || exit 0
  case "$again" in n|N|no|NO) info "끝냅니다."; exit 0 ;; esac
done
