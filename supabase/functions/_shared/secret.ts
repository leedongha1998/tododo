// 비밀값 비교.
//
// judge-dispute는 verify_jwt = false로 배포되므로 헤더 `x-judge-secret` 검사가 유일한 관문이다.
// 짧은 비교(`===`)는 앞부분이 맞을수록 오래 걸려 값이 한 글자씩 새어 나갈 수 있어 상수 시간으로 본다.

const encoder = new TextEncoder();

/// 길이가 달라도 비교 시간이 내용에 따라 달라지지 않는 비교. 빈 값은 항상 false다
/// (시크릿이 설정되지 않은 상태에서 빈 헤더가 통과하면 안 된다).
export function constantTimeEquals(a: string, b: string): boolean {
  if (a.length === 0 || b.length === 0) return false;

  const left = encoder.encode(a);
  const right = encoder.encode(b);

  // 길이 차이도 결과에 섞되, 반복 횟수는 들어온 값의 길이로만 정해진다.
  let diff = left.length ^ right.length;
  for (let i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i % right.length];
  }
  return diff === 0;
}
