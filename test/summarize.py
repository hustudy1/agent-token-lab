#!/usr/bin/env python3
"""ab_test.sh 결과 폴더를 읽어 조건별 평균 비용·토큰을 표로 정리한다.

사용법: python3 test/summarize.py <결과 폴더>

- <조건>_r<회차>.json      작업 실행 결과
- <조건>_r<회차>_on.json   (예전 방식) Caveman을 따로 켠 호출 결과. 있으면 해당 회차에 더한다.
결과는 화면에 출력하고 <결과 폴더>/summary.md 에도 저장한다.
"""
import glob
import json
import os
import re
import sys

LABEL = {"A": "기준 (둘 다 끔)", "B": "RTK만", "C": "Caveman만", "D": "둘 다"}
FIELDS = [
    ("warm", "환산비용*"),
    ("context", "컨텍스트"),
    ("cost", "비용($)"),
    ("input", "입력"),
    ("cache_write", "캐시쓰기"),
    ("cache_read", "캐시읽기"),
    ("output", "출력"),
    ("turns", "턴"),
]


def load(path):
    d = json.load(open(path, encoding="utf-8"))
    u = d.get("usage") or {}
    return {
        "cost": d.get("total_cost_usd") or 0.0,
        "input": u.get("input_tokens", 0),
        "cache_write": u.get("cache_creation_input_tokens", 0),
        "cache_read": u.get("cache_read_input_tokens", 0),
        "output": u.get("output_tokens", 0),
        "turns": d.get("num_turns") or 0,
        # 모델이 처리한 전체 입력. 캐시 적중 여부와 관계없이 같은 작업이면 비슷해야 한다
        "context": u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0),
        "denials": len(d.get("permission_denials") or []),
        "error": bool(d.get("is_error")),
    }


def warm_equiv(v):
    """캐시 영향을 뺀 비교용 값 (입력 토큰 환산).

    모든 입력을 캐시 읽기(입력 단가의 0.1배)로, 출력을 입력 단가의 5배로 친다.
    Claude 모델 대부분의 가격 비율이며, 캐시가 늘 따뜻한 상태를 가정한다.
    실제 청구액이 아니라 조건끼리 비교하기 위한 값이다.
    """
    return v["context"] * 0.1 + v["output"] * 5


def add(a, b):
    return {k: (a[k] + b[k]) if k not in ("error",) else (a[k] or b[k]) for k in a}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    runs = {}  # 조건 -> [회차별 값]
    notes = []
    for path in sorted(glob.glob(os.path.join(out, "*.json"))):
        m = re.match(r"([ABCD])_r(\d+)\.json$", os.path.basename(path))
        if not m:
            continue
        cond, rnd = m.group(1), m.group(2)
        try:
            v = load(path)
        except (ValueError, OSError):
            notes.append(f"{os.path.basename(path)}: JSON을 읽지 못해 제외")
            continue
        on = os.path.join(out, f"{cond}_r{rnd}_on.json")
        if cond in "CD":
            if os.path.exists(on):
                v = add(v, load(on))
        if v["error"]:
            notes.append(f"{cond}_r{rnd}: is_error=true (결과를 확인하세요)")
        if v["denials"]:
            notes.append(f"{cond}_r{rnd}: 권한 거부 {v['denials']}건 (허용 도구 밖의 명령을 시도함)")
        v["warm"] = warm_equiv(v)
        runs.setdefault(cond, []).append(v)

    if not runs:
        sys.exit(f"{out} 에 결과 JSON이 없습니다.")

    mean = {c: {k: sum(r[k] for r in rs) / len(rs) for k, _ in FIELDS} for c, rs in runs.items()}
    base = mean.get("A")

    lines = []
    meta = os.path.join(out, "meta.txt")
    if os.path.exists(meta):
        lines += ["```", open(meta, encoding="utf-8").read().strip(), "```", ""]
    lines.append("## 조건별 평균")
    lines.append("")
    lines.append("| 조건 | 횟수 | " + " | ".join(h for _, h in FIELDS) + " |")
    lines.append("|---|---|" + "---|" * len(FIELDS))
    for c in sorted(mean):
        cells = []
        for k, _ in FIELDS:
            v = mean[c][k]
            cell = f"{v:.4f}" if k == "cost" else f"{v:,.0f}" if k != "turns" else f"{v:.1f}"
            if base and c != "A" and base[k]:
                cell += f" ({(v - base[k]) / base[k] * 100:+.0f}%)"
            cells.append(cell)
        lines.append(f"| {c} {LABEL[c]} | {len(runs[c])} | " + " | ".join(cells) + " |")
    lines.append("")
    lines.append("괄호 안은 A(기준) 대비 차이입니다. 반복 횟수가 적으면 우연한 차이가 클 수 있습니다.")
    lines.append("")
    lines.append("- **환산비용\***: 캐시 영향을 뺀 비교용 값입니다. 컨텍스트 × 0.1 + 출력 × 5 (입력 토큰 환산, 캐시가 늘 따뜻하다고 가정). **조건 비교는 이 열로 하세요.**")
    lines.append("- **비용($)**: 실제 청구 추정입니다. 그 회차에 캐시를 새로 썼는지(약 $0.1) 다시 읽었는지(약 $0.02)에 크게 좌우되어, 반복 횟수가 적으면 조건 비교에 쓰기 어렵습니다.")
    lines.append("- **컨텍스트**: 입력 + 캐시쓰기 + 캐시읽기. 모델이 처리한 전체 입력입니다.")
    lines.append("")
    lines.append("## 회차별")
    lines.append("")
    lines.append("| 조건 | 회차 | 환산비용* | 비용($) | 턴 | 출력 | 캐시쓰기 | 캐시읽기 |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for c in sorted(runs):
        for i, r in enumerate(runs[c], 1):
            lines.append(f"| {c} | {i} | {r['warm']:,.0f} | {r['cost']:.4f} | {r['turns']} | {r['output']:,} | {r['cache_write']:,} | {r['cache_read']:,} |")
    if notes:
        lines += ["", "## 참고", ""] + [f"- {n}" for n in notes]

    text = "\n".join(lines) + "\n"
    open(os.path.join(out, "summary.md"), "w", encoding="utf-8").write(text)
    print(text)


if __name__ == "__main__":
    main()
