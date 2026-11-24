// 증거 사진 버킷을 service 롤로 다루는 판단들(submit-evidence·delete-account 공용).
//
// 앱 사용자는 증거 사진을 지울 수 없다(20261124130000). 그래서 남은 삭제는 전부 여기를 지나고,
// 여기서 지키는 규칙 두 가지가 2026-11-24 보안 점검의 높음 1·2를 막는다.
//   - 제출을 받기 전에 사진이 **실제로 있는지** 본다. 빈 경로로 먼저 접수해 시각을 잡고 나중에
//     사진을 올리는 길을 막는다(한 번 올라간 경로는 사용자가 바꿀 수도 지울 수도 없다).
//   - 접수가 거부돼 사진을 치울 때 **어떤 제출도 가리키지 않는 경로만** 지운다. 그러지 않으면
//     판정 중에 내 제출 경로를 다시 보내 거부당하는 것만으로 서버가 그 사진을 대신 지워 주고,
//     AI 재판정이 사진을 못 받아 대결이 무효가 된다.
//
// DB·Storage 호출은 `EvidenceStore`로 감싸 deno test에서 가짜로 바꿔 끼운다.

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

export const EVIDENCE_BUCKET = 'battle_evidence';

export interface EvidenceStore {
  /// 폴더 바로 아래의 파일 이름들. 실패하면 null.
  listNames(folder: string, search?: string): Promise<string[] | null>;
  /// 지우기. 성공하면 true.
  remove(paths: string[]): Promise<boolean>;
  /// 이 경로를 가리키는 제출 행이 있는가. 알 수 없으면 null.
  isReferenced(path: string): Promise<boolean | null>;
}

/// `battleId/userId/name.jpg`를 폴더와 이름으로 나눈다. 모양이 다르면 null.
export function splitObjectPath(path: string): { folder: string; name: string } | null {
  const index = path.lastIndexOf('/');
  if (index <= 0 || index === path.length - 1) return null;
  return { folder: path.slice(0, index), name: path.slice(index + 1) };
}

/// 사진이 실제로 올라가 있는가. **확인하지 못하면 없다고 본다**(접수하지 않는 쪽이 안전하다 —
/// 정상 사용자는 다시 누르면 된다).
export async function evidenceExists(store: EvidenceStore, path: string): Promise<boolean> {
  const parts = splitObjectPath(path);
  if (parts === null) return false;
  const names = await store.listNames(parts.folder, parts.name);
  return names !== null && names.includes(parts.name);
}

export type RemoveOutcome = 'removed' | 'kept' | 'failed';

/// 접수가 거부된 사진을 치운다. **어떤 제출도 가리키지 않을 때만** 지우고, 참조 여부를 알 수
/// 없으면 지우지 않는다(남은 파일은 비용이고, 잘못 지운 파일은 대결 결과다).
export async function removeIfUnreferenced(
  store: EvidenceStore,
  path: string,
): Promise<RemoveOutcome> {
  const referenced = await store.isReferenced(path);
  if (referenced !== false) return 'kept';
  return (await store.remove([path])) ? 'removed' : 'failed';
}

/// 탈퇴한 사람이 올린 사진을 전부 지운다. 대결마다 `battleId/userId/` 폴더 하나다. 실패한
/// 폴더 수를 돌려준다(0이면 전부 지웠다).
export async function removeUserEvidence(
  store: EvidenceStore,
  userId: string,
  battleIds: string[],
): Promise<number> {
  let failed = 0;
  for (const battleId of new Set(battleIds)) {
    const folder = `${battleId}/${userId}`;
    const names = await store.listNames(folder);
    if (names === null) {
      failed += 1;
      continue;
    }
    if (names.length === 0) continue;
    if (!(await store.remove(names.map((name) => `${folder}/${name}`)))) failed += 1;
  }
  return failed;
}

/// 실제 Supabase(service 롤) 위의 구현.
export function supabaseEvidenceStore(client: SupabaseClient): EvidenceStore {
  const bucket = client.storage.from(EVIDENCE_BUCKET);
  return {
    async listNames(folder, search) {
      const { data, error } = await bucket.list(folder, {
        limit: 1000,
        ...(search ? { search } : {}),
      });
      if (error || !data) {
        console.error(`증거 사진 목록 실패(${folder}): ${error?.message ?? '내용 없음'}`);
        return null;
      }
      // 하위 폴더 항목은 id가 null이다. 파일만 남긴다.
      return data.filter((entry) => entry.id !== null).map((entry) => entry.name);
    },
    async remove(paths) {
      const { error } = await bucket.remove(paths);
      if (error) {
        console.error(`증거 사진 삭제 실패: ${error.message}`);
        return false;
      }
      return true;
    },
    async isReferenced(path) {
      const { data, error } = await client
        .from('battle_submissions')
        .select('id')
        .eq('object_path', path)
        .limit(1);
      if (error || !data) {
        console.error(`증거 사진 참조 확인 실패: ${error?.message ?? '내용 없음'}`);
        return null;
      }
      return data.length > 0;
    },
  };
}
