---
name: workflow-bash-heredoc-limit
description: Bash 도구로 큰 파일을 heredoc으로 쓰면 길이 한계에 걸린다 — 300~400줄 단위로 쪼개 append해야 한다
metadata:
  type: feedback
---

이 환경의 Bash 도구는 **한 호출에 담은 명령 문자열이 길면 조용히 깨진다.** 큰 SQL 마이그레이션이나
TS 파일을 heredoc 하나로 쓰려 하면 두 가지 증상이 난다.

- 아주 길면(대략 20k자 이상): `ENAMETOOLONG: name too long, uv_spawn` — 아무 파일도 만들어지지 않는다.
- 어중간히 길면(대략 8k자 이상, 특히 heredoc 여러 개를 한 호출에 넣을 때):
  `unexpected EOF while looking for matching '` — 내용에 따옴표·백틱 불균형이 없어도 난다.
  역시 파일이 만들어지지 않거나 일부만 남는다.

**How to apply:** 파일을 만들 때 `cat > file <<'EOF'`로 첫 덩어리를 쓰고, 이어지는 부분은
`cat >> file <<'EOF'`로 **300~400줄 / 10k자 이하**씩 나눠 붙인다. 한 호출에 heredoc은 하나만 둔다
(`mkdir`·`rm`·`grep` 같은 짧은 명령은 같이 둬도 된다). 매 덩어리 끝에 `grep -c "" file`로 누적 줄 수를
확인하면 중간에 날아간 덩어리를 바로 알 수 있다. 922줄 마이그레이션은 8덩어리, 475줄 SQL 스모크는
5덩어리로 썼다(2026-10-29, mutual-judge 3단계).

**Why:** 실패가 "따옴표가 안 맞는다"는 엉뚱한 메시지로 나오기 때문에, 내용에서 원인을 찾느라 시간을
버리게 된다. 원인은 내용이 아니라 길이다.

이 환경에는 **python이 없다**(`python`은 Microsoft Store 앱 실행 별칭으로 가로채진다). 파일 중간에
텍스트를 끼워 넣을 때는 `awk`/`perl`/`sed`/`node`를 쓴다 — 예: `awk 'NR==380{print; ...}'`로 특정 줄
뒤에 다른 파일 내용을 삽입. 참고: [[workflow-edit-hooks]]
