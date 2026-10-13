#!/usr/bin/env python3
"""사용량·절약 보기 (setup.sh 메뉴에서 호출)

  npx ccusage@latest claude daily   --json | python3 tools/usage_report.py mix
  npx ccusage@latest claude session --json | python3 tools/usage_report.py sessions
  python3 tools/usage_report.py context [프로젝트 폴더]

mix·sessions 는 ccusage JSON(v20 기준)을 표준 입력으로 받는다.
context 는 매 세션 항상 실리는 파일·스킬·MCP 서버를 점검한다.
"""
import glob
import json
import os
import re
import sys
import unicodedata

def width(text):
    """화면 폭: 한글 등 전각 문자는 2칸."""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def pad(text, w):
    """전각 문자를 고려해 왼쪽 정렬로 w칸을 채운다."""
    return text + " " * max(0, w - width(text))


# 가격 비율 (입력 단가 = 1). Claude 모델 대부분의 공개 가격 비율이다.
WEIGHT = {"read": 0.1, "write": 1.25, "output": 5.0, "input": 1.0}


def load_stdin():
    try:
        return json.load(sys.stdin)
    except ValueError:
        print("  사용 기록을 읽지 못했습니다. (ccusage 출력이 JSON이 아님)")
        sys.exit(0)


def mix():
    t = load_stdin().get("totals") or {}
    rows = [
        ("캐시 읽기 (매 턴 이전 대화 다시 읽기)", t.get("cacheReadTokens", 0), WEIGHT["read"]),
        ("캐시 쓰기 (새 내용 저장)", t.get("cacheCreationTokens", 0), WEIGHT["write"]),
        ("출력 (모델이 쓴 글)", t.get("outputTokens", 0), WEIGHT["output"]),
        ("입력 (캐시 안 된 입력)", t.get("inputTokens", 0), WEIGHT["input"]),
    ]
    tok = sum(r[1] for r in rows)
    if not tok:
        print("  기록이 없습니다.")
        return
    cost = sum(r[1] * r[2] for r in rows)
    print("  " + pad("항목", 40) + pad("토큰", 16) + pad("토큰 비율", 12) + "비용 비율(추정)")
    for name, n, k in rows:
        print("  " + pad(name, 40) + pad("{:,}".format(n), 16) + pad("{:.1f}%".format(n / tok * 100), 12)
              + "{:.1f}%".format(n * k / cost * 100))
    ctx = (rows[0][1] * WEIGHT["read"] + rows[1][1] * WEIGHT["write"]) / cost * 100
    out = rows[2][1] * WEIGHT["output"] / cost * 100
    print()
    print("  비용 비율은 가격 비율(캐시 읽기 0.1, 캐시 쓰기 1.25, 출력 5, 입력 1)로 추정한 값입니다.")
    print("  - 컨텍스트(캐시 읽기+쓰기)가 비용의 약 {:.0f}%입니다. 가장 큰 절약 지점입니다.".format(ctx))
    print("    주제가 바뀌면 /clear 로 새 대화를 시작하고, 상시 로딩을 줄이세요 (메뉴의 '상시 로딩 점검').")
    print("  - 출력은 비용의 약 {:.0f}%입니다. Caveman이 줄일 수 있는 건 이 부분뿐입니다.".format(out))
    print("  총합: {:,} 토큰, API 단가 환산 ${:.2f}".format(t.get("totalTokens", tok), t.get("totalCost", 0)))


def local_time(iso):
    """ccusage의 UTC 시각(ISO 8601)을 이 컴퓨터의 현지 시각으로 바꾼다."""
    from datetime import datetime
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return iso[:16].replace("T", " ")


def sessions():
    ss = load_stdin().get("sessions") or []
    if not ss:
        print("  기록이 없습니다.")
        return
    ss.sort(key=lambda s: s.get("totalCost", 0), reverse=True)
    total = sum(s.get("totalCost", 0) for s in ss) or 1
    print("  " + pad("#", 4) + pad("마지막 활동(현지)", 18) + pad("비용($)", 10) + pad("캐시 읽기", 15) + pad("출력", 10) + "프로젝트")
    for i, s in enumerate(ss[:10], 1):
        # ccusage는 경로의 / 를 - 로 바꿔 저장한다. 홈 폴더 부분만 ~/ 로 줄여 보여준다 (근사)
        proj = re.sub(r"^-(Users|home)-[^-]+-", "~/", s.get("projectPath", ""))
        when = local_time(s.get("lastActivity") or "")
        print("  " + pad(str(i), 4) + pad(when, 18) + pad("{:.2f}".format(s.get("totalCost", 0)), 10)
              + pad("{:,}".format(s.get("cacheReadTokens", 0)), 15) + pad("{:,}".format(s.get("outputTokens", 0)), 10) + proj)
    top = sum(s.get("totalCost", 0) for s in ss[:10])
    print()
    print("  전체 {}개 대화 중 상위 10개가 비용의 {:.0f}%입니다.".format(len(ss), top / total * 100))
    print("  비싼 대화는 대개 오래 이어진 대화입니다. 매 턴 앞의 대화를 전부 다시 읽기 때문입니다.")
    print("  주제가 바뀌면 /clear 로 새로 시작하는 것이 가장 확실한 절약입니다.")


# ---------- 상시 로딩 점검 ----------

def est(text):
    """대략적인 토큰 수 (추정): 영문·기호 4글자당 1, 한글 등 그 밖의 글자 1.5글자당 1."""
    a = sum(1 for c in text if ord(c) < 128)
    return int(a / 4 + (len(text) - a) / 1.5)


def read(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return None


class Context:
    def __init__(self, home):
        self.home = home
        self.total = 0
        self.tips = []

    def short(self, p):
        return p.replace(self.home, "~", 1)

    def report(self, label, path, note=""):
        t = read(path)
        if t is None:
            return None
        n = est(t)
        self.total += n
        lines = t.count("\n") + (0 if t.endswith("\n") else 1)
        print("  " + pad(label, 26) + pad("{}줄".format(lines), 8) + pad("{:,}바이트".format(len(t.encode())), 14)
              + pad("약 {:,}토큰".format(n), 14) + self.short(path) + note)
        if os.path.basename(path) == "CLAUDE.md" and lines > 200:
            self.tips.append("{} 가 {}줄입니다. 공식 권장은 200줄 미만입니다. "
                             "특정 작업용 지시는 스킬로 옮기세요.".format(self.short(path), lines))
        # @import 는 시작할 때 함께 로딩된다
        for m in re.finditer(r"(?m)^@(\S+)", t):
            ref = os.path.expanduser(m.group(1))
            if not os.path.isabs(ref):
                ref = os.path.join(os.path.dirname(path), ref)
            self.report("  └ @import", os.path.normpath(ref), " (시작할 때 함께 로딩)")
        return t


def skill_desc_tokens(skill_md):
    t = read(skill_md) or ""
    m = re.match(r"---\r?\n(.*?)\r?\n---", t, re.S)
    if not m:
        return 0
    d = re.search(r"(?ms)^description:\s*[>|]?\s*(.*?)(?=^[\w-]+:|\Z)", m.group(1))
    return est(d.group(1)) if d else 0


def context(proj):
    home = os.path.expanduser("~")
    codex = os.environ.get("CODEX_HOME") or os.path.join(home, ".codex")
    c = Context(home)

    print("[Claude Code]")
    c.report("전역 CLAUDE.md", os.path.join(home, ".claude", "CLAUDE.md"))
    for r in sorted(glob.glob(os.path.join(home, ".claude", "rules", "*.md"))):
        if re.search(r"(?m)^paths:", (read(r) or "")[:500]):
            print("  " + pad("규칙 (필요할 때만)", 26) + c.short(r))
        else:
            c.report("규칙 (항상)", r)

    if proj:
        proj = os.path.abspath(os.path.expanduser(proj))
        if not os.path.isdir(proj):
            print("  [주의] 프로젝트 폴더가 없습니다: " + proj + " (전역 설정만 점검합니다)")
            proj = ""
    if proj:
        has_claude = False
        for name in ("CLAUDE.md", os.path.join(".claude", "CLAUDE.md"), "CLAUDE.local.md"):
            if c.report("프로젝트 " + name, os.path.join(proj, name)) is not None:
                has_claude = True
        agents = os.path.join(proj, "AGENTS.md")
        if os.path.exists(agents):
            if has_claude:
                print("  " + pad("프로젝트 AGENTS.md", 26) + "CLAUDE.md가 있어 Claude Code는 기본으로 읽지 않음 (Codex는 읽음)")
                claude_text = "".join(read(os.path.join(proj, n)) or "" for n in ("CLAUDE.md", os.path.join(".claude", "CLAUDE.md")))
                if "@AGENTS.md" not in claude_text:
                    c.tips.append("이 프로젝트는 CLAUDE.md가 있어 Claude Code가 AGENTS.md를 읽지 않습니다. "
                                  "같은 지시를 쓰려면 CLAUDE.md에 '@AGENTS.md' 한 줄을 넣으세요 (링크만으로는 자동으로 읽지 않음).")
            else:
                c.report("프로젝트 AGENTS.md", agents, " (CLAUDE.md가 없어 Claude Code도 읽음)")

    skills = sorted(glob.glob(os.path.join(home, ".claude", "skills", "*", "SKILL.md")))
    desc = sum(skill_desc_tokens(s) for s in skills)
    c.total += desc
    print("  " + pad("스킬 이름·설명", 26) + pad("{}개".format(len(skills)), 22)
          + pad("약 {:,}토큰".format(desc), 14) + "~/.claude/skills (본문은 쓸 때만 로딩)")
    if len(skills) > 10:
        c.tips.append("스킬이 {}개입니다. 설명이 매 세션 실립니다. 안 쓰는 스킬은 지우거나 "
                      "/skills 에서 'Name only'로 바꾸세요.".format(len(skills)))

    mcp = {}
    cj = read(os.path.join(home, ".claude.json"))
    if cj:
        try:
            d = json.loads(cj)
            mcp.update({k: "전역" for k in (d.get("mcpServers") or {})})
            if proj:
                mcp.update({k: "이 프로젝트" for k in (((d.get("projects") or {}).get(proj) or {}).get("mcpServers") or {})})
        except ValueError:
            pass
    if proj:
        mj = read(os.path.join(proj, ".mcp.json"))
        if mj:
            try:
                mcp.update({k: ".mcp.json" for k in (json.loads(mj).get("mcpServers") or {})})
            except ValueError:
                pass
    print("  " + pad("MCP 서버", 26) + pad("{}개".format(len(mcp)), 8)
          + (", ".join("{}({})".format(k, v) for k, v in mcp.items()) or "-"))
    if mcp:
        c.tips.append("MCP 서버 {}개: 도구 정의는 기본으로 필요할 때만 로딩되지만, 안 쓰는 서버는 /mcp 에서 끄세요. "
                      "가능하면 CLI 도구(gh 등)가 더 가볍습니다.".format(len(mcp)))

    if os.path.isdir(codex):
        print("\n[Codex]")
        for name in ("AGENTS.override.md", "AGENTS.md"):
            c.report("전역 " + name, os.path.join(codex, name))
        cfg = read(os.path.join(codex, "config.toml")) or ""
        n = len(re.findall(r"(?m)^\[mcp_servers\.[^.\]]+\]", cfg))
        print("  " + pad("MCP 서버 (config.toml)", 26) + "{}개".format(n))

    print()
    print("  상시 로딩 합계 (추정): 약 {:,}토큰. 시스템 프롬프트·도구 정의(보통 수천~수만 토큰)는 빠진 값입니다.".format(c.total))
    print("  정확한 수치는 Claude Code 안에서 /context 로 확인하세요.")
    if not proj:
        print("  프로젝트별 CLAUDE.md·AGENTS.md도 보려면: bash setup.sh context <프로젝트 폴더>")
    if c.tips:
        print("\n  줄일 수 있는 곳")
        for t in c.tips:
            print("  - " + t)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "mix":
        mix()
    elif cmd == "sessions":
        sessions()
    elif cmd == "context":
        context(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        sys.exit(__doc__)
