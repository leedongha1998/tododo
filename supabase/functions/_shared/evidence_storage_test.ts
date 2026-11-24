import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  type EvidenceStore,
  evidenceExists,
  removeIfUnreferenced,
  removeUserEvidence,
  splitObjectPath,
} from './evidence_storage.ts';

/// 폴더별 파일 이름과 제출이 가리키는 경로를 들고 있는 가짜 버킷.
function fakeStore(options: {
  folders?: Record<string, string[]>;
  referenced?: string[];
  failList?: boolean;
  failRemove?: boolean;
  unknownReference?: boolean;
}) {
  const folders = structuredClone(options.folders ?? {});
  const removed: string[] = [];
  const store: EvidenceStore = {
    listNames(folder, search) {
      if (options.failList) return Promise.resolve(null);
      const names = folders[folder] ?? [];
      // 실제 Storage의 search는 부분 일치다 — 정확히 같은 이름만 고르는 일은 호출하는 쪽 몫이다.
      return Promise.resolve(search ? names.filter((name) => name.includes(search)) : names);
    },
    remove(paths) {
      if (options.failRemove) return Promise.resolve(false);
      removed.push(...paths);
      return Promise.resolve(true);
    },
    isReferenced(path) {
      if (options.unknownReference) return Promise.resolve(null);
      return Promise.resolve((options.referenced ?? []).includes(path));
    },
  };
  return { store, removed };
}

Deno.test('경로는 폴더와 파일 이름으로 나뉜다', () => {
  assertEquals(splitObjectPath('b/u/a.jpg'), { folder: 'b/u', name: 'a.jpg' });
  assertEquals(splitObjectPath('a.jpg'), null);
  assertEquals(splitObjectPath('b/u/'), null);
  assertEquals(splitObjectPath('/a.jpg'), null);
});

Deno.test('사진이 실제로 있어야 접수한다 — 빈 경로로 시각을 먼저 잡지 못한다', async () => {
  const { store } = fakeStore({ folders: { 'b/u': ['a.jpg', 'xa.jpg'] } });
  assertEquals(await evidenceExists(store, 'b/u/a.jpg'), true);
  assertEquals(await evidenceExists(store, 'b/u/later.jpg'), false);
  // 부분 일치(search)에 걸려도 이름이 정확히 같지 않으면 없는 것이다.
  assertEquals(await evidenceExists(store, 'b/u/x.jpg'), false);
  assertEquals(await evidenceExists(store, 'b/u/'), false);
});

Deno.test('목록을 못 읽으면 없다고 본다(접수하지 않는다)', async () => {
  const { store } = fakeStore({ folders: { 'b/u': ['a.jpg'] }, failList: true });
  assertEquals(await evidenceExists(store, 'b/u/a.jpg'), false);
});

Deno.test('거부된 업로드는 지우지만 제출이 가리키는 사진은 지우지 않는다', async () => {
  const { store, removed } = fakeStore({ referenced: ['b/u/submitted.jpg'] });
  assertEquals(await removeIfUnreferenced(store, 'b/u/new.jpg'), 'removed');
  // 판정 중에 내 제출 경로를 다시 보내 거부당해도 서버가 대신 지워 주지 않는다.
  assertEquals(await removeIfUnreferenced(store, 'b/u/submitted.jpg'), 'kept');
  assertEquals(removed, ['b/u/new.jpg']);
});

Deno.test('참조 여부를 알 수 없으면 지우지 않는다', async () => {
  const { store, removed } = fakeStore({ unknownReference: true });
  assertEquals(await removeIfUnreferenced(store, 'b/u/new.jpg'), 'kept');
  assertEquals(removed, []);
});

Deno.test('삭제가 실패하면 failed', async () => {
  const { store } = fakeStore({ failRemove: true });
  assertEquals(await removeIfUnreferenced(store, 'b/u/new.jpg'), 'failed');
});

Deno.test('탈퇴: 내가 참가한 대결마다 내 폴더의 사진만 전부 지운다', async () => {
  const { store, removed } = fakeStore({
    folders: { 'b1/u': ['1.jpg', '2.jpg'], 'b1/o': ['other.jpg'], 'b2/u': [] },
  });
  assertEquals(await removeUserEvidence(store, 'u', ['b1', 'b2', 'b1']), 0);
  assertEquals(removed, ['b1/u/1.jpg', 'b1/u/2.jpg']);
});

Deno.test('탈퇴: 목록·삭제 실패는 센다', async () => {
  assertEquals(
    await removeUserEvidence(fakeStore({ failList: true }).store, 'u', ['b1', 'b2']),
    2,
  );
  assertEquals(
    await removeUserEvidence(
      fakeStore({ folders: { 'b1/u': ['1.jpg'] }, failRemove: true }).store,
      'u',
      ['b1'],
    ),
    1,
  );
});
