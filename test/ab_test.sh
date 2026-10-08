#!/usr/bin/env bash
#
# Caveman·RTK 효과 A/B 측정 (macOS / Linux)
#   같은 작업을 4가지 조건으로 반복 실행하고, claude -p 의 JSON 결과(비용·토큰)를 비교합니다.
#
#   사용법: bash test/ab_test.sh [옵션]       자세한 설명은 test/01_measure.md
#
# 확인 기준: Claude Code 2.1.292 · 2026-10-07 · macOS 기본 bash 3.2에서 동작
#
# 조건
#   A  기준      RTK 끔(훅 전체 끔) · Caveman 끔
#   B  RTK       RTK 켬             · Caveman 끔
#   C  Caveman   RTK 끔(훅 전체 끔) · Caveman 켬 (프롬프트 맨 앞에 /caveman full)
#   D  둘 다     RTK 켬             · Caveman 켬

set -u

SCRIPT_VERSION="2026-10-07"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPO="$PWD"
RUNS=3
MODEL=""
MAX_TURNS=20
CONDITIONS="A B C D"
OUT=""
DRY_RUN=0
ASSUME_YES=0
TASK="이 저장소의 폴더와 파일 구성을 살펴보고, git log 와 git status 결과를 확인해서 이 저장소가 무엇인지 5줄 이내로 설명해 줘. 파일은 절대 수정하지 마."

# 훅을 모두 끄는 설정 (RTK 끄기용). 공식 설정 키: disableAllHooks
HOOKS_OFF='{"disableAllHooks":true}'


# ---------- 출력 ----------

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
die()  { printf '\n%s[중단]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'EOF'
Caveman·RTK 효과 A/B 측정

  bash test/ab_test.sh --repo <저장소> --model sonnet            기본: 조건 4개 × 3회
  bash test/ab_test.sh --repo <저장소> --runs 1 --model sonnet   빠른 시험 (조건 4개 × 1회)

옵션
  --repo <경로>        작업할 git 저장소 (기본: 현재 폴더)
  --task "<작업>"      모든 조건에 똑같이 줄 작업 (기본: 저장소 구조·git log 요약)
  --runs <N>           조건마다 반복 횟수 (기본 3)
  --model <모델>       예: sonnet, opus, haiku (기본: 계정 기본 모델. 비쌀 수 있음)
  --max-turns <N>      실행 1회의 최대 턴 수 (기본 20)
  --conditions "A B"   돌릴 조건만 고르기 (기본 "A B C D")
  --out <폴더>         결과 저장 위치 (기본 test/results/<날짜-시간>)
  --dry-run            실행할 명령만 출력
  -y, --yes            확인 질문 없이 진행
  -h, --help           이 도움말

조건
  A 기준(둘 다 끔)  B RTK만  C Caveman만  D 둘 다

결과
  <out>/*.json      실행마다 claude -p 결과 원본
  <out>/summary.md  조건별 평균 비용·토큰과 A 대비 차이
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)       REPO="${2:-}"; shift ;;
    --task)       TASK="${2:-}"; shift ;;
    --runs)       RUNS="${2:-}"; shift ;;
    --model)      MODEL="${2:-}"; shift ;;
    --max-turns)  MAX_TURNS="${2:-}"; shift ;;
    --conditions) CONDITIONS="${2:-}"; shift ;;
    --out)        OUT="${2:-}"; shift ;;
    --dry-run)    DRY_RUN=1 ;;
    -y|--yes)     ASSUME_YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) usage; die "알 수 없는 옵션: $1" ;;
  esac
  shift
done

# ---------- 확인 ----------

case "$RUNS" in ''|*[!0-9]*|0) die "--runs 는 1 이상의 숫자여야 합니다: $RUNS" ;; esac
case "$MAX_TURNS" in ''|*[!0-9]*|0) die "--max-turns 는 1 이상의 숫자여야 합니다: $MAX_TURNS" ;; esac
for c in $CONDITIONS; do
  case "$c" in A|B|C|D) : ;; *) die "조건은 A B C D 중에서 고르세요: $c" ;; esac
done
have claude  || die "claude CLI가 없습니다."
have python3 || die "python3가 없습니다 (결과 정리에 필요)."
[ -d "$REPO" ] || die "저장소 폴더가 없습니다: $REPO"
REPO="$(cd "$REPO" && pwd)"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || warn "$REPO 는 git 저장소가 아닙니다. 기본 작업(git log 요약)이 의미 없을 수 있습니다."

[ -n "$OUT" ] || OUT="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
# 실행 중에 저장소 폴더로 cd 하므로 결과 폴더는 절대 경로여야 한다
case "$OUT" in /*) : ;; *) OUT="$PWD/$OUT" ;; esac
MODEL_ARGS=""
[ -n "$MODEL" ] && MODEL_ARGS="--model $MODEL"

# RTK·Caveman 설치 상태 (없으면 B·C·D가 A와 같아지므로 경고)
RTK_STATE="없음"; CAVE_STATE="없음"
if have rtk && grep -qiE 'rtk hook' "$HOME/.claude/settings.json" 2>/dev/null; then RTK_STATE="$(rtk --version 2>/dev/null)"; fi
[ -d "$HOME/.claude/skills/caveman" ] && CAVE_STATE="설치됨"

printf '%sCaveman·RTK A/B 측정%s (%s)\n' "$C_B" "$C_0" "$SCRIPT_VERSION"
info "저장소:   $REPO"
info "작업:     $TASK"
info "모델:     ${MODEL:-계정 기본값}"
info "조건:     $CONDITIONS   반복: ${RUNS}회   최대 턴: $MAX_TURNS"
info "RTK:      $RTK_STATE   Caveman: $CAVE_STATE"
info "결과:     $OUT"
case " $CONDITIONS " in *" B "*|*" D "*) [ "$RTK_STATE" = "없음" ] && warn "RTK 훅이 없어 B·D가 A·C와 같아집니다." ;; esac
case " $CONDITIONS " in *" C "*|*" D "*) [ "$CAVE_STATE" = "없음" ] && warn "caveman 스킬이 없어 C·D가 A·B와 같아집니다." ;; esac

# shellcheck disable=SC2086
set -- $CONDITIONS
info "claude -p 호출: 총 $(( $# * RUNS ))회 (구독 사용량을 씁니다)"
[ "$DRY_RUN" -eq 1 ] && info "dry-run: 실제로 실행하지 않습니다."

if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  printf '\n계속할까요? [y/N] '
  read -r answer
  case "$answer" in y|Y|yes|YES) : ;; *) die "사용자가 취소했습니다." ;; esac
fi

# ---------- 실행 ----------

[ "$DRY_RUN" -eq 1 ] || mkdir -p "$OUT"

# run_claude 이름 프롬프트 [추가 인자...] : 저장소 폴더에서 claude -p 를 실행하고 JSON을 <이름>.json 에 저장
run_claude() {
  # 함수끼리 변수를 덮어쓰지 않도록 local 로 둔다 (bash 함수 변수는 기본이 전역)
  local name prompt rc
  name="$1"; prompt="$2"; shift 2
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    [dry-run] claude -p "%s" %s --output-format json --max-turns %s %s\n' \
      "$prompt" "$*" "$MAX_TURNS" "$MODEL_ARGS"
    return 0
  fi
  # MODEL_ARGS는 "--model 이름" 두 단어라 따옴표 없이 펼친다
  # shellcheck disable=SC2086
  (cd "$REPO" && claude -p "$prompt" "$@" --output-format json --max-turns "$MAX_TURNS" $MODEL_ARGS \
      < /dev/null > "$OUT/$name.json" 2> "$OUT/$name.err")
  rc=$?
  if [ $rc -ne 0 ] || ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$OUT/$name.json" 2>/dev/null; then
    warn "$name 실패 (종료 코드 $rc). $OUT/$name.err 를 확인하세요."
    return 1
  fi
  python3 - "$OUT/$name.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); u = d.get("usage") or {}
print("    {:<10} 비용 ${:.4f}  턴 {:>2}  입력 {:>6}  캐시쓰기 {:>7}  캐시읽기 {:>8}  출력 {:>6}".format(
    sys.argv[1].rsplit("/", 1)[-1][:-5], d.get("total_cost_usd") or 0, d.get("num_turns") or 0,
    u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0),
    u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)))
PY
  return 0
}

run_condition() {   # $1: 조건, $2: 회차
  local c r name hooks prompt
  c="$1"; r="$2"; name="${c}_r${r}"
  hooks=""
  case "$c" in A|C) hooks="--settings $HOOKS_OFF" ;; esac
  # Caveman은 같은 프롬프트 맨 앞에 /caveman full 을 붙여 한 번의 호출로 켠다.
  # (켜는 호출과 작업 호출을 나누면 세션 시작 비용이 두 번 들어 공정한 비교가 안 된다. 2026-10-07 시험으로 확인)
  prompt="$TASK"
  case "$c" in C|D) prompt="/caveman full
$TASK" ;; esac
  # 허용 도구: 읽기 전용 작업에 필요한 것만. 공백이 든 항목이 있어 개별 인자로 넘긴다.
  # RTK가 켜지면 git log 가 rtk git log 로 바뀌고, 권한은 바뀐 명령 기준으로 검사하므로 Bash(rtk *)도 허용한다.
  # shellcheck disable=SC2086
  run_claude "$name" "$prompt" $hooks --allowedTools "Read" "Grep" "Glob" "Bash(git *)" "Bash(ls *)" \
    "Bash(cat *)" "Bash(head *)" "Bash(wc *)" "Bash(find *)" "Bash(rtk *)"
}

r=1
while [ "$r" -le "$RUNS" ]; do
  # 회차마다 조건 순서를 한 칸씩 돌린다 (뒤 순서가 앞 실행의 캐시 덕을 보는 편향을 줄이기 위해)
  # shellcheck disable=SC2086
  set -- $CONDITIONS
  shift_n=$(( (r - 1) % $# ))
  i=0
  while [ "$i" -lt "$shift_n" ]; do first="$1"; shift; set -- "$@" "$first"; i=$((i + 1)); done
  step "${r}회차 (순서: $*)"
  for c in "$@"; do run_condition "$c" "$r"; done
  r=$((r + 1))
done

[ "$DRY_RUN" -eq 1 ] && { step "dry-run 끝"; exit 0; }

# ---------- 정리 ----------

# 같은 결과 폴더에 이어서 실행하면 기존 기록 뒤에 덧붙인다
[ -f "$OUT/meta.txt" ] && printf '\n--- 추가 실행 ---\n' >> "$OUT/meta.txt"
cat >> "$OUT/meta.txt" <<EOF
날짜: $(date '+%Y-%m-%d %H:%M:%S')
저장소: $REPO ($(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo 'git 아님'))
작업: $TASK
모델: ${MODEL:-계정 기본값}
조건: $CONDITIONS / 반복: $RUNS / 최대 턴: $MAX_TURNS
Claude Code: $(claude --version 2>/dev/null | head -1)
RTK: $RTK_STATE / Caveman: $CAVE_STATE
EOF

step "결과 정리"
python3 "$SCRIPT_DIR/summarize.py" "$OUT"
info "원본: $OUT/*.json   요약: $OUT/summary.md"
