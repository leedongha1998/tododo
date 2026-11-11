// 판정 기준 캐시(criteria-cache)의 유사도 임계값 측정.
//
// 근거: docs/specs/criteria-cache/design.md 8장, plan.md "## 임계값 결과표"(오너 승인 대상).
//
// 돌리는 법 (키를 가진 사람만 돌릴 수 있다):
//   export GEMINI_API_KEY=...
//   deno run --allow-net --allow-env tool/criteria_cache_threshold.ts
//
// **운영과 같은 코드 경로를 쓴다** - Edge Function이 쓰는 embedText·normalizeTitle·l2Normalize·
// cosineSimilarity를 그대로 import한다. 그래야 여기서 잰 숫자가 실제 조회와 같은 공간의 값이다.
//
// **DB도 캐시도 건드리지 않는다**(읽기도 쓰기도 없다. 임베딩 호출과 산수뿐).
// 호출 수: 제목 중복을 빼고 캐시해서 부르므로 쌍 26개에 대해 40여 회다(임베딩 한도 안).
//
// 출력은 마크다운 표다. 그대로 plan.md의 "## 임계값 결과표"에 붙이고, 오너는 요약의 한 줄만
// 본다 - **그룹 B 오적중이 0인가.**
//
// 임계값을 정하는 규칙(측정 전에 못 박은 것. 숫자를 보고 규칙을 고르지 않는다):
//   1. 그룹 B에서 오적중이 하나라도 있으면 임계값을 올린다. 적중률은 목표가 아니다.
//   2. 임계값 = (그룹 B 최고 유사도 + 0.02)를 0.01 단위로 올림.
//   3. 그 결과 그룹 A가 하나도 안 묶여도 그대로 간다(= 정규화 일치에서만 적중하는 캐시가 된다).
//   4. 그룹 B 최고가 0.97 이상이면 구현을 멈추고 오너에게 보고한다(반대 뜻을 벡터로 가를 수 없다는
//      뜻이다. 임계값 0.98+로 사실상 정규화 일치만 쓰거나 벡터 경로를 접는다).

import { EMBEDDING_DIM, EMBEDDING_TASK_TYPE, embedText, embeddingModel } from '../supabase/functions/_shared/gemini.ts';
import {
  CRITERIA_CACHE_MIN_SIMILARITY,
  cosineSimilarity,
  l2Normalize,
  normalizeTitle,
} from '../supabase/functions/_shared/criteria_cache.ts';

type Group = 'A' | 'B' | 'C';

interface Pair {
  id: string;
  group: Group;
  kind: string;
  a: string;
  b: string;
}

/// 그룹 A - 묶여도 되는 쌍(같은 주제, 표현만 다름). 못 묶여도 손해는 AI 호출 1회뿐이다.
/// 그룹 B - **절대 묶이면 안 되는 쌍**(묶이면 판정의 근거가 틀린다). spec이 요구한 네 유형 전부.
/// 그룹 C - 어느 쪽이어도 되는 쌍(판정 대상이 아니라 숫자의 분포를 보는 자료).
const PAIRS: Pair[] = [
  { id: 'A1', group: 'A', kind: '같은 주제', a: '방 청소하기', b: '방 치우기' },
  { id: 'A2', group: 'A', kind: '같은 주제', a: '아침 운동', b: '아침에 운동하기' },
  { id: 'A3', group: 'A', kind: '같은 주제', a: '설거지하기', b: '설거지 끝내기' },
  { id: 'A4', group: 'A', kind: '같은 주제', a: '책상 정리', b: '책상 정리하기' },
  { id: 'A5', group: 'A', kind: '같은 주제', a: '이불 개기', b: '이불 정리하기' },
  { id: 'A6', group: 'A', kind: '같은 주제', a: '분리수거 하기', b: '재활용 분리배출 하기' },

  { id: 'B1', group: 'B', kind: '부정·반대', a: '방 청소하기', b: '방 어지럽히기' },
  { id: 'B2', group: 'B', kind: '부정·반대', a: '설탕 끊기', b: '디저트 먹기' },
  { id: 'B3', group: 'B', kind: '부정·반대', a: '일찍 자기', b: '밤새우기' },
  { id: 'B4', group: 'B', kind: '부정·반대', a: '금연하기', b: '담배 피우기' },
  { id: 'B5', group: 'B', kind: '부정·반대', a: '라면 안 먹기', b: '라면 먹기' },
  { id: 'B6', group: 'B', kind: '숫자·시간대', a: '아침 산책 30분', b: '저녁 산책 1시간' },
  { id: 'B7', group: 'B', kind: '숫자·시간대', a: '팔굽혀펴기 10개', b: '팔굽혀펴기 100개' },
  { id: 'B8', group: 'B', kind: '숫자·시간대', a: '물 1리터 마시기', b: '물 3리터 마시기' },
  { id: 'B9', group: 'B', kind: '숫자·시간대', a: '아침 7시 기상', b: '아침 10시 기상' },
  { id: 'B10', group: 'B', kind: '상위어/하위어', a: '운동하기', b: '턱걸이 10개' },
  { id: 'B11', group: 'B', kind: '상위어/하위어', a: '청소하기', b: '화장실 변기 닦기' },
  { id: 'B12', group: 'B', kind: '상위어/하위어', a: '요리하기', b: '계란말이 만들기' },
  { id: 'B13', group: 'B', kind: '증명 가능/불가능', a: '독서 30분', b: '책 정리하기' },
  { id: 'B14', group: 'B', kind: '증명 가능/불가능', a: '명상 10분', b: '요가 매트 펴기' },
  { id: 'B15', group: 'B', kind: '증명 가능/불가능', a: '영어 공부하기', b: '영어책 펴 놓기' },

  { id: 'C1', group: 'C', kind: '기준선', a: '쓰레기 버리기', b: '분리수거 하기' },
  { id: 'C2', group: 'C', kind: '기준선', a: '머리 감기', b: '샤워하기' },
  { id: 'C3', group: 'C', kind: '기준선', a: '산책하기', b: '조깅하기' },
  { id: 'C4', group: 'C', kind: '기준선', a: '아침 운동', b: '저녁 운동' },
  { id: 'C5', group: 'C', kind: '기준선', a: '설거지하기', b: '주방 청소하기' },
];

/// 정규화가 같은 문자열을 만들었는지 눈으로 보는 쌍(유사도 1.000이어야 한다).
const NORMALIZATION_PAIRS: [string, string][] = [
  ['  아침   운동  ', '아침 운동'],
  ['Morning Run', 'morning run'],
  ['아침　운동', '아침 운동'],
];

const vectors = new Map<string, number[]>();

async function vectorOf(title: string): Promise<number[]> {
  // 운영과 같은 입력을 쓴다 - 조회에 넣는 값은 정규화된 제목이다.
  const key = normalizeTitle(title);
  const cached = vectors.get(key);
  if (cached) return cached;
  const values = l2Normalize(await embedText(key));
  vectors.set(key, values);
  return values;
}

async function similarityOf(a: string, b: string): Promise<number> {
  // 정규화 결과가 같으면 같은 벡터다. 호출을 아낀다(= 운영의 정규화 일치 경로와 같은 판단).
  if (normalizeTitle(a) === normalizeTitle(b)) return 1;
  return cosineSimilarity(await vectorOf(a), await vectorOf(b));
}

function fixed(value: number): string {
  return value.toFixed(3);
}

if (import.meta.main) {
  if (!Deno.env.get('GEMINI_API_KEY')) {
    console.error('GEMINI_API_KEY가 없습니다. export GEMINI_API_KEY=... 뒤에 다시 실행하세요.');
    Deno.exit(1);
  }

  const threshold = CRITERIA_CACHE_MIN_SIMILARITY;
  const rows: { pair: Pair; similarity: number }[] = [];

  for (const pair of PAIRS) {
    rows.push({ pair, similarity: await similarityOf(pair.a, pair.b) });
  }

  const today = new Date().toISOString().slice(0, 10);
  const lines: string[] = [];
  lines.push(
    `측정: ${today} / ${embeddingModel} / ${EMBEDDING_TASK_TYPE} / ${EMBEDDING_DIM}차원 / L2 정규화`,
  );
  lines.push(`임계값 후보: ${fixed(threshold)}`);
  lines.push('');
  lines.push('| # | 그룹 | 제목 A | 제목 B | 유사도 | 임계값에서 묶이는가 | 기대 | 판정 |');
  lines.push('|---|---|---|---|---|---|---|---|');

  for (const { pair, similarity } of rows) {
    const bound = similarity >= threshold;
    const expectation = pair.group === 'A'
      ? '묶여도 됨'
      : pair.group === 'B'
      ? '**안 묶여야 함**'
      : '아무 쪽이나';
    const verdict = pair.group === 'B' ? (bound ? '**오적중**' : 'OK') : pair.group === 'A' ? (bound ? 'OK(적중)' : 'OK(미적중)') : '-';
    lines.push(
      `| ${pair.id} | ${pair.group} ${pair.kind} | ${pair.a} | ${pair.b} | ${fixed(similarity)} | ` +
        `${bound ? '묶임' : '안 묶임'} | ${expectation} | ${verdict} |`,
    );
  }

  const groupMax = (group: Group) =>
    Math.max(...rows.filter((row) => row.pair.group === group).map((row) => row.similarity));
  const groupMin = (group: Group) =>
    Math.min(...rows.filter((row) => row.pair.group === group).map((row) => row.similarity));

  const bMax = groupMax('B');
  const bWorst = rows.find((row) => row.pair.group === 'B' && row.similarity === bMax)!.pair;
  const recommended = Math.ceil((bMax + 0.02) * 100) / 100;
  const aBound = rows.filter((row) => row.pair.group === 'A' && row.similarity >= recommended).length;
  const bBound = rows.filter((row) => row.pair.group === 'B' && row.similarity >= recommended).length;
  const aCount = rows.filter((row) => row.pair.group === 'A').length;
  const bCount = rows.filter((row) => row.pair.group === 'B').length;

  lines.push('');
  lines.push('요약');
  lines.push(`- 그룹 B 최고 유사도: ${bWorst.id} = ${fixed(bMax)}   <- 임계값은 이 값보다 위여야 한다`);
  lines.push(`- 그룹 A 최저 유사도: ${fixed(groupMin('A'))}`);
  lines.push(`- 그룹 C 분포: ${fixed(groupMin('C'))} ~ ${fixed(groupMax('C'))}`);
  lines.push(`- 권장 임계값: ${fixed(recommended)}   (B 최고 + 0.02를 0.01 단위로 올림)`);
  lines.push(
    `- 그 임계값에서 그룹 A 적중: ${aBound}/${aCount}, 그룹 B 오적중: **${bBound}/${bCount}**(0이어야 한다)`,
  );
  lines.push(
    `- 지금 코드의 임계값(${fixed(threshold)})에서 그룹 B 오적중: ` +
      `${rows.filter((row) => row.pair.group === 'B' && row.similarity >= threshold).length}/${bCount}`,
  );
  if (bMax >= 0.97) {
    lines.push('- **경고: 그룹 B 최고가 0.97 이상이다. 구현을 멈추고 오너에게 보고할 자리다(design 8.3 규칙 4).**');
  }

  lines.push('');
  lines.push('정규화 확인(유사도 1.000이어야 한다 = 정규화가 같은 문자열을 만들었다)');
  for (const [a, b] of NORMALIZATION_PAIRS) {
    const same = normalizeTitle(a) === normalizeTitle(b);
    lines.push(`- ${JSON.stringify(a)} vs ${JSON.stringify(b)}: ${same ? '1.000' : '다른 키'}`);
  }

  console.log(lines.join('\n'));
}
