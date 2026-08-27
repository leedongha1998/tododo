# battle-identity 설계

## 참고
spec.md: `docs/specs/battle-identity/spec.md`

이 설계는 신규 기능이 아니라 기존 "대결" 판정 메커니즘 변경이다. 핵심 변경 4가지(spec.md 확정 결정 3~8):
1. 속도전도 "증거 제출 → 상대 승인/이의제기" 절차를 거쳐야만 완료·승부가 확정된다(자기 신고 폐지).
2. 품질전 증거는 사진 필수로 격상(텍스트만으로는 불가). 속도전 증거는 사진 또는 텍스트 중 최소 하나.
3. 두 유형 모두 **양쪽 참가자가 각자 증거를 제출하고 서로의 증거를 판정**해야 종결된다(대칭 구조, 결정 6).
4. **이의제기 = 그 참가자의 완료 무효화**(결정 7). 더 이상 "하나라도 이의제기면 무조건 전체 미결"이 아니다 — 속도전은 유효한(승인된) 완료들 사이에서 승부를 가린다.

### 설계 원칙: 속도전 = 품질전과 동일한 증거/승인 구조 위에 "결과 판정 규칙"만 다름
두 유형은 **절차**(양쪽이 각자 증거 제출 → 서로 상대 증거를 approve/dispute)를 완전히 공유하고, **결과 판정**만 다르다.

| | 속도전(speed) | 품질전(quality) |
|---|---|---|
| 필수 증거 | 사진 또는 텍스트 중 최소 하나 | 사진 필수 |
| 양쪽 다 승인 | `finished`, 승자 = 증거 제출 시각이 이른 쪽 | `finished`, 승자 없음 |
| 한쪽만 승인 | `finished`, 승자 = **승인받은 쪽**(제출이 늦었더라도) | `disputed`, 승자 없음 |
| 양쪽 다 이의제기 | `disputed`, 승자 없음 | `disputed`, 승자 없음 |
| 결과 확정 시점 | **양쪽 판정이 모두 내려진 뒤** | dispute는 즉시, approve는 양쪽 승인 시 |

여기서 가장 중요한 구현상 귀결: **속도전에서는 이의제기를 해도 그 즉시 대결이 끝나지 않는다.** 이의제기당한 쪽의 완료가 무효화될 뿐이고, 상대 쪽 완료가 유효한지(=아직 판정 안 된 나머지 증거가 approve될지 dispute될지)를 알아야 결과가 정해지기 때문이다. 반면 품질전은 종전대로 dispute 하나로 즉시 `disputed`가 된다.

따라서 이 설계는 기존 `submit_quality_evidence` / `decide_quality_evidence` RPC를 품질전 전용에서 **속도전/품질전 공용**으로 일반화하고(`submit_evidence` / `decide_evidence`), `decide_evidence` 안에서만 유형별 결과 판정을 분기한다. 완전히 새로운 RPC를 만들지 않는다.

## 상태 전이

기존 CLAUDE.md 전이표: `pending → active → judging(품질전만) → finished | disputed | cancelled`.

변경 후: **`judging`을 속도전도 거친다.** 두 유형이 `judging`까지는 동일하고, `judging`에서 나가는 조건만 다르다.

```
pending --(join_battle)--> active --(둘 중 누구든 첫 증거 제출)--> judging

[quality] judging --(어느 쪽 증거든 dispute)-------------------> disputed (승자 없음)
          judging --(양쪽 증거 모두 approve)---------------------> finished (승자 없음)

[speed]   judging --(양쪽 판정이 모두 내려짐)--> 유효한 완료 개수로 분기
            · 2개(둘 다 approve)  -> finished, winner = evidence_submitted_at이 이른 쪽
            · 1개(한쪽만 approve) -> finished, winner = approve받은 쪽
            · 0개(둘 다 dispute)  -> disputed, winner 없음
          judging --(한쪽 판정만 내려짐)--> judging 유지(결과 미확정)
```

`cancelled`는 `pending` 상태에서만 발생(기존과 동일, 이번 변경과 무관). `disputed`/`finished`는 종결 상태이며 이후 전이는 없다.

한쪽이 증거를 끝내 제출하지 않으면 대결은 `judging`에 머문 채 종결되지 않는다 — spec.md 트레이드오프에 "방치된 대결" 문제로 기록되어 있고 이 설계에서 해결하지 않는다(타임아웃/자동 판정 같은 장치를 만들지 않는다).

## 화면

기존 `battle_detail_screen.dart`의 `_SpeedSection`(완료 버튼만)과 `_QualitySection`(증거 제출 + 승인/이의제기)을 하나의 공용 위젯 `_EvidenceSection`으로 통합한다. 유형별로 다른 것은 (a) 필수 증거 종류, (b) 종료/미결 시 결과 문구뿐이다.

### `_EvidenceSection` 상태
- **로딩/에러**: 기존 `battleDetailProvider`의 AsyncValue 처리 그대로 유지(변경 없음).
- **내 증거 제출 전** (`canSubmitEvidence == true`): 증거 입력 폼.
  - 품질전: 사진 선택 버튼만 노출(카메라/갤러리 선택 바텀시트). 사진 없이는 제출 버튼 비활성.
  - 속도전: 사진 선택 버튼 + 텍스트 입력란 둘 다 노출. 사진이 있거나 텍스트가 비어있지 않으면 제출 버튼 활성화(최소 하나).
  - 제출 버튼을 누르면: (사진이 있는 경우) Storage 업로드 → 업로드 성공 후 `submit_evidence` RPC 호출. 업로드 중에는 버튼에 로딩 인디케이터, 중복 탭 방지로 비활성화.
  - 업로드/제출 실패 시: 스낵바로 에러 노출(기존 `battleEvidenceSubmitFailed` 재사용), 상태는 그대로 유지해 재시도 가능해야 한다(에러를 삼키지 않는다 — CLAUDE.md).
  - 속도전에서는 제출 시각이 곧 승부 기준 시각이므로, 폼 상단에 그 사실을 안내하는 한 줄을 둔다(신규 문자열 `battleSpeedEvidenceNotice`: "지금 제출한 시각이 승부 기준이 돼요. 상대가 승인해야 완료로 인정됩니다.").
- **내 증거 제출 완료, 상대 판정 대기중** (`me.evidenceSubmittedAt != null && me.decision == null`): 내가 제출한 증거 표시(사진이면 서명 URL로 썸네일, 텍스트면 본문) + "상대방의 판정을 기다리는 중이에요"(기존 `battleDecisionWaiting`).
- **내 증거가 승인됨** (`me.decision == 'approve'`): 기존 `battleDecisionApproved`("상대방이 승인했어요.").
- **내 증거가 이의제기당함** (`me.decision == 'dispute'`, 아직 `judging`): 신규 문자열 `battleMyEvidenceDisputed`("상대방이 내 증거에 이의를 제기했어요. 내 완료는 무효로 처리돼요."). 속도전에서는 이 시점에도 아직 대결이 끝나지 않았음을 사용자가 이해해야 하므로 결과 대기 문구를 함께 둔다.
- **상대가 아직 증거를 제출하지 않음** (`opponent.evidenceSubmittedAt == null`): 기존 `battleEvidenceWaitingOpponentSubmit`.
- **상대 증거 검토 가능** (`canReviewOpponentEvidence == true`): 상대 증거 표시(사진 썸네일/텍스트) + 승인/이의제기 버튼(기존 `battleApprove`/`battleDispute`).
  - 이의제기 버튼은 결과를 되돌릴 수 없으므로 확인 다이얼로그를 한 번 띄운다. 다이얼로그 본문은 유형에 따라 다르다 — 속도전은 "상대의 완료가 무효가 돼요"(신규 `battleDisputeConfirmSpeed`), 품질전은 "대결이 미결로 끝나요"(신규 `battleDisputeConfirmQuality`).
- **내가 상대를 판정했고 상대는 아직 나를 판정 안 함** (속도전 전용으로 눈에 띄는 상태): 상대 증거 + 내가 내린 판정 결과 + "아직 결과가 확정되지 않았어요"(신규 `battleSpeedAwaitingBothDecisions`: "상대방이 내 증거를 판정하면 결과가 확정돼요."). 이 상태가 없으면 사용자가 "이의제기를 눌렀는데 왜 안 끝나지?"라고 느낀다.
- **종료(`finished`)** — 상단 결과 배너:
  - 품질전: 기존 `battleQualityFinished`("모두 승인되어 대결이 종료됐어요.").
  - 속도전 승리(`didIWinSpeedBattle`): 기존 `battleYouWon` + 사유 한 줄.
    - 상대가 이의제기당해 이긴 경우(`wasOpponentEvidenceDisputed`): 신규 `battleWonByOpponentDisputed`("상대방의 증거가 이의제기로 무효가 되어 이겼어요.")
    - 둘 다 승인되고 내가 먼저 제출한 경우: 신규 `battleWonBySpeed`("먼저 완료를 증명해서 이겼어요.")
  - 속도전 패배: 기존 `battleYouLost` + 사유 한 줄.
    - 내 증거가 무효가 된 경우(`wasMyEvidenceDisputed`): 신규 `battleLostByDisputed`("내 증거가 이의제기로 무효가 되어 졌어요.")
    - 상대가 먼저 제출한 경우: 신규 `battleLostBySpeed`("상대방이 먼저 완료를 증명했어요.")
- **미결(`disputed`)**: 상단 배너.
  - 품질전: 기존 `battleDisputedMessage`("이의제기가 있어 아직 미결 상태예요.").
  - 속도전: 신규 `battleSpeedDisputedMessage`("양쪽 모두 이의제기를 받아 유효한 완료가 없어요. 승자 없이 미결로 끝났어요."). 속도전에서 `disputed`는 **양쪽 다 이의제기당한 경우에만** 도달하므로 문구를 구분한다.
  - 두 경우 모두 양쪽 증거는 읽기 전용으로 계속 표시(승인/이의제기 버튼 미노출 — 종결 상태이므로 서버 `decide_evidence`도 거부한다).

사진 썸네일은 private 버킷이므로 매번 서명 URL(signed URL)을 받아 `Image.network`로 렌더링한다(아래 API 계약 참고). 서명 URL 발급 실패 시에도 화면 전체를 깨뜨리지 않고 해당 썸네일 자리만 에러 아이콘 + 재시도로 대체한다.

### 전적/목록 화면 영향
`myBattlesProvider`/`BattleSummary` 기반의 목록·전적 화면은 `battle.status`와 `winner_id`만 보고 결과를 표시하므로 이번 변경으로 구조를 바꿀 필요는 없다. 다만 **속도전도 `disputed`로 끝날 수 있게 되었으므로**, 속도전 항목에서 `disputed`를 표시하지 못하는 분기가 있으면 미결 표시를 추가한다(현재 요약 화면이 `disputed`를 품질전 전용으로 다루고 있는지 구현 단계에서 확인 필요).

### 제거되는 것
- `_SpeedSection` 위젯, `_completeSpeedTask` 핸들러, `battleRepository.completeSpeedTask` 호출부.
- 관련 문자열 `battleComplete`, `battleCompleted`, `battleCompleteFailed`, `battleSpeedDone`, `battleSpeedWaiting`, `battleSpeedWaitingOpponent`는 더 이상 쓰이지 않으므로 함께 정리한다(`battleYouWon`/`battleYouLost`는 결과 배너에서 계속 쓰이므로 유지).

## 데이터 흐름

1. **화면 진입**: `battleDetailProvider(battleId)` → `fetchBattle` + `fetchParticipants` + `fetchDisplayNames` → `BattleDetail` 조립 → `_EvidenceSection`이 getter 조합으로 위 상태 중 하나를 렌더링. 이 흐름 자체는 기존과 동일하며, 유형 분기(`battle.type == 'speed'`)가 "완전히 다른 위젯"이 아니라 "필수 증거 종류 + 결과 문구"로 축소된다.
2. **증거 제출**:
   - (사진인 경우) `battle_evidence` 버킷에 업로드 → 오브젝트 경로 문자열을 얻는다.
   - 레포지토리가 `submit_evidence(p_battle_id, p_evidence_type, p_evidence_content)` RPC 호출. `p_evidence_content`는 사진이면 스토리지 경로, 텍스트면 사용자가 입력한 본문.
   - 서버가 `evidence_submitted_at = now()`를 찍는다 → **이 값이 속도전 승부 기준 시각**이다(클라이언트 시간 미사용).
   - 성공 시 `battleDetailProvider`/`myBattlesProvider` invalidate.
3. **판정(승인/이의제기)**: `decide_evidence(p_battle_id, p_target_user_id, p_decision)` RPC 호출 → 서버가 (a) 해당 참가자의 완료 유효/무효를 기록하고, (b) 유형별 결과 판정(위 상태 전이표)과 `winner_id` 계산까지 전부 처리 → invalidate. **클라이언트는 승패를 계산하지 않는다**(CLAUDE.md).
   - 속도전에서 내 판정만 내려진 경우 서버는 상태를 바꾸지 않고 `judging`을 유지한다 → 화면은 "결과 대기" 상태로 갱신된다.
4. **증거 사진 조회**: `evidence_type == 'photo'`인 참가자 행을 렌더링할 때 5분짜리 서명 URL을 받아 표시한다.

## API 계약

### DB 스키마 변경

`battle_participants.evidence_type`은 이미 `check (evidence_type in ('photo', 'text'))`로 정의돼 있어 스키마 변경이 필요 없다(어떤 값이 허용되는가는 대결 유형에 따라 RPC 안에서 검증). `evidence_content`는 사진인 경우 원문이 아니라 **Storage 오브젝트 경로 문자열**을 담는다는 의미가 추가된다(컬럼 변경 없음, 의미 확장).

`battle_participants.decision`(`approve`/`dispute`)의 의미도 확장된다: 기존에는 "품질전 증거에 대한 상대의 판정"이었으나, 이제 **"이 참가자의 완료가 유효한가"**를 나타내는 유형 공통 필드다. `decision = 'approve'`인 참가자만 유효한 완료를 가진 것으로 취급한다. 마이그레이션에 이 의미를 주석으로 남긴다(기존 `20260818220100_battles.sql`의 "speed: completed_at만 사용" 주석도 함께 정정 대상).

`battle_participants.completed_at` 컬럼은 제거한다. 근거: 완료·승부 확정 시각이 유형에 상관없이 `evidence_submitted_at` 하나로 통일되므로(spec 결정 5) 별도 `completed_at`은 어긋날 수 있는 중복 소스다. 아직 배포 전(MVP, 실사용자 데이터 없음)이라 호환 부담이 없다 — CLAUDE.md "스키마 변경은 마이그레이션 파일로만" 규칙에 따라 `alter table public.battle_participants drop column completed_at;`을 새 마이그레이션에 포함한다.

새 Storage 버킷 `battle_evidence`를 추가한다(비공개). 경로 규칙: `{battle_id}/{user_id}/evidence.jpg`.

```sql
insert into storage.buckets (id, name, public) values ('battle_evidence', 'battle_evidence', false);

-- 업로드: 본인 폴더에만, 그리고 실제로 이 대결의 참가자이고 증거 제출 가능한 상태(active/judging)일 때만.
create policy "participants can upload own evidence"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id = ((storage.foldername(name))[1])::uuid
        and auth.uid() in (b.creator_id, b.opponent_id)
        and b.status in ('active', 'judging')
    )
  );

-- 재제출(upsert) 시 update도 열어야 한다. insert 정책과 동일 조건.
create policy "participants can update own evidence"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'battle_evidence' and (storage.foldername(name))[2] = auth.uid()::text)
  with check (
    bucket_id = 'battle_evidence'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.battles b
      where b.id = ((storage.foldername(name))[1])::uuid
        and auth.uid() in (b.creator_id, b.opponent_id)
        and b.status in ('active', 'judging')
    )
  );

-- 조회: 참가자라면 본인/상대 증거 사진 둘 다 읽을 수 있어야 승인 화면에서 보여줄 수 있다.
create policy "participants can read battle evidence"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'battle_evidence'
    and exists (
      select 1 from public.battles b
      where b.id = ((storage.foldername(name))[1])::uuid
        and auth.uid() in (b.creator_id, b.opponent_id)
    )
  );
```

(삭제 정책은 만들지 않는다 — 증거 삭제 기능 자체가 MVP 범위에 없다.)

### RPC 변경

`complete_speed_task(uuid)`는 삭제한다(`drop function public.complete_speed_task(uuid);`).

`submit_quality_evidence`를 **`submit_evidence`로 일반화**한다(품질전 전용 제약 제거 + 유형별 증거 종류 검증 추가):

```sql
create or replace function public.submit_evidence(
  p_battle_id uuid,
  p_evidence_type text,
  p_evidence_content text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
begin
  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status not in ('active', 'judging') then
    raise exception '증거를 제출할 수 없는 상태입니다.';
  end if;

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if p_evidence_type not in ('photo', 'text') then
    raise exception '증거 유형이 올바르지 않습니다.';
  end if;

  -- 품질전은 사진 필수(텍스트만으로는 불가). 속도전은 사진/텍스트 둘 다 허용.
  if v_battle.type = 'quality' and p_evidence_type <> 'photo' then
    raise exception '품질전은 사진 증거가 필수입니다.';
  end if;

  update public.battle_participants
  set
    evidence_type = p_evidence_type,
    evidence_content = p_evidence_content,
    evidence_submitted_at = now(),
    decision = null,
    decision_at = null
  where battle_id = p_battle_id and user_id = auth.uid();

  if v_battle.status = 'active' then
    update public.battles set status = 'judging' where id = p_battle_id;
  end if;
end;
$$;
```

> 위 `decision = null` 초기화(재제출 시 판정 리셋)는 기존 `submit_quality_evidence`의 동작을 그대로 옮긴 것이다. 다만 새 규칙에서는 이 동작의 의미가 커진다 — "## 결정 필요" 참고.

`decide_quality_evidence`를 **`decide_evidence`로 일반화**한다. 핵심 변경은 결과 판정부다: 품질전은 종전대로 dispute 즉시 종결, 속도전은 **양쪽 판정이 모두 내려진 뒤에** 유효한 완료 개수로 분기한다.

```sql
create or replace function public.decide_evidence(
  p_battle_id uuid,
  p_target_user_id uuid,
  p_decision text
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_battle public.battles%rowtype;
  v_target public.battle_participants%rowtype;  -- 내가 판정하는 상대의 행
  v_self public.battle_participants%rowtype;    -- 상대가 판정한 내 행
begin
  if p_decision not in ('approve', 'dispute') then
    raise exception '판정 값이 올바르지 않습니다.';
  end if;

  select * into v_battle from public.battles where id = p_battle_id for update;

  if v_battle is null then
    raise exception '대결을 찾을 수 없습니다.';
  end if;

  if v_battle.status <> 'judging' then
    raise exception '판정할 수 있는 상태가 아닙니다.';
  end if;

  if auth.uid() not in (v_battle.creator_id, v_battle.opponent_id) then
    raise exception '이 대결의 참가자가 아닙니다.';
  end if;

  if auth.uid() = p_target_user_id then
    raise exception '본인의 증거는 직접 판정할 수 없습니다.';
  end if;

  select * into v_target
  from public.battle_participants
  where battle_id = p_battle_id and user_id = p_target_user_id
  for update;

  if v_target is null or v_target.evidence_submitted_at is null then
    raise exception '판정할 증거가 없습니다.';
  end if;

  if v_target.decision is not null then
    raise exception '이미 판정된 증거입니다.';
  end if;

  update public.battle_participants
  set decision = p_decision, decision_at = now()
  where battle_id = p_battle_id and user_id = p_target_user_id;

  -- 판정 반영 후 두 참가자 행을 다시 읽어 결과를 계산한다.
  select * into v_target
  from public.battle_participants
  where battle_id = p_battle_id and user_id = p_target_user_id;

  select * into v_self
  from public.battle_participants
  where battle_id = p_battle_id and user_id = auth.uid();

  -- 품질전: 승자 개념이 없다. 이의제기 하나면 즉시 미결, 양쪽 승인이면 종료.
  if v_battle.type = 'quality' then
    if p_decision = 'dispute' then
      update public.battles set status = 'disputed' where id = p_battle_id;
    elsif v_self.decision = 'approve' then
      update public.battles set status = 'finished', finished_at = now() where id = p_battle_id;
    end if;
    return;
  end if;

  -- 속도전: 이의제기는 "그 사람의 완료 무효화"일 뿐 즉시 종결이 아니다.
  -- 양쪽 판정이 모두 내려져야 유효한 완료가 몇 개인지 확정되므로 그때만 결과를 낸다.
  if v_self.decision is null then
    return;  -- 상대가 아직 내 증거를 판정하지 않음 -> judging 유지
  end if;

  if v_self.decision = 'approve' and v_target.decision = 'approve' then
    -- 둘 다 유효 -> 증거 제출 시각이 이른 쪽 승리
    update public.battles
    set status = 'finished',
        finished_at = now(),
        winner_id = case
          when v_self.evidence_submitted_at <= v_target.evidence_submitted_at then v_self.user_id
          else v_target.user_id
        end
    where id = p_battle_id;
  elsif v_self.decision = 'approve' then
    -- 내 완료만 유효(상대는 이의제기로 무효) -> 제출이 늦었더라도 내가 승리
    update public.battles
    set status = 'finished', finished_at = now(), winner_id = v_self.user_id
    where id = p_battle_id;
  elsif v_target.decision = 'approve' then
    -- 상대 완료만 유효 -> 상대 승리
    update public.battles
    set status = 'finished', finished_at = now(), winner_id = v_target.user_id
    where id = p_battle_id;
  else
    -- 둘 다 무효 -> 유효한 완료 없음, 승자 없이 미결
    update public.battles set status = 'disputed' where id = p_battle_id;
  end if;
end;
$$;
```

메모:
- `disputed`일 때 `finished_at`을 채우지 않는 것은 기존 `decide_quality_evidence`의 동작을 그대로 유지한 것이다(이번 변경 범위 밖).
- 동시 제출 시각 동률(`v_self.evidence_submitted_at = v_target.evidence_submitted_at`)은 `timestamptz` 정밀도상 실질적으로 발생하지 않는다고 보고 `<=`로 처리한다(규칙에 영향 없는 구현 세부사항).
- `winner_id`는 오직 이 함수 안에서만 채워진다. 클라이언트는 `battles`의 `status`/`winner_id`를 직접 UPDATE할 수 없다(기존 RLS 그대로).

```sql
grant execute on function public.submit_evidence(uuid, text, text) to authenticated;
grant execute on function public.decide_evidence(uuid, uuid, text) to authenticated;
-- complete_speed_task, submit_quality_evidence, decide_quality_evidence는 drop function으로 제거.
```

### 도메인 유닛 테스트 (CLAUDE.md: 판정/상태 전이는 반드시 유닛 테스트)
판정 로직 본체가 DB 함수라 SQL 레벨 검증이 필요하지만 이 머신에는 로컬 Postgres가 없다(CLAUDE.md 개발 환경 항목). 최소한 아래 케이스가 표로 정리되어 어딘가에서 검증돼야 한다는 점만 설계 차원에서 명시한다 — 검증 수단(로컬 Docker/클라우드 프로젝트/Dart 측 순수 함수 추출 중 무엇으로 할지)은 plan.md 영역이다.

| # | 유형 | A 판정 | B 판정 | 기대 status | 기대 winner |
|---|---|---|---|---|---|
| 1 | speed | approve | approve | finished | 제출 시각 이른 쪽 |
| 2 | speed | approve | dispute | finished | approve받은 쪽(제출 늦어도) |
| 3 | speed | dispute | dispute | disputed | 없음 |
| 4 | speed | approve | (미판정) | judging | 없음 |
| 5 | speed | dispute | (미판정) | judging | 없음 |
| 6 | quality | approve | approve | finished | 없음 |
| 7 | quality | approve | dispute | disputed | 없음 |
| 8 | quality | dispute | (미판정) | disputed | 없음 |

### 클라이언트 레포지토리 변경 (`battle_repository.dart`)

```dart
Future<void> submitEvidence(String battleId, String evidenceType, String content) {
  return _client.rpc('submit_evidence', params: {
    'p_battle_id': battleId,
    'p_evidence_type': evidenceType, // 'photo' | 'text'
    'p_evidence_content': content,   // photo면 storage 경로, text면 본문
  });
}

Future<void> decideEvidence(String battleId, String targetUserId, String decision) {
  return _client.rpc('decide_evidence', params: {
    'p_battle_id': battleId,
    'p_target_user_id': targetUserId,
    'p_decision': decision,
  });
}

Future<String> uploadEvidencePhoto(String battleId, Uint8List bytes) async {
  final myId = _client.auth.currentUser!.id;
  final path = '$battleId/$myId/evidence.jpg';
  await _client.storage.from('battle_evidence').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
      );
  return path;
}

Future<String> createEvidencePhotoUrl(String path) {
  return _client.storage.from('battle_evidence').createSignedUrl(path, 300);
}
```

`completeSpeedTask`, 기존 `submitQualityEvidence`, `decideQualityEvidence`는 제거하고 위 시그니처로 대체한다(품질전 전용이라는 이름이 더 이상 정확하지 않으므로 이름도 함께 바꾼다).

### `battle_detail.dart` getter 변경

- **제거**: `canCompleteSpeedTask`, `isWaitingForOpponentSpeed` — 자기 신고만으로 완료되는 흐름이 폐지되어 더 이상 유효한 개념이 아니다.
- **유지(변경 없음, 이미 유형 무관하게 작성돼 있어 속도전에 그대로 적용됨)**: `canSubmitEvidence`, `canReviewOpponentEvidence`, `isDisputed`, `didIWinSpeedBattle`, `isQualityFinished`.
- **추가**:
  ```dart
  bool get isFinished => battle.status == 'finished';
  bool get isSpeedFinished => battle.type == 'speed' && isFinished;

  // 품질전만 사진 필수. 속도전은 사진/텍스트 중 최소 하나(서버와 동일 규칙을 클라에서도 막아
  // 불필요한 RPC 실패 왕복을 줄인다 — 판정이 아니라 입력 검증이므로 클라 계산 금지 규칙과 무관).
  bool get requiresPhotoEvidence => battle.type == 'quality';

  // 완료 유효/무효 (decision은 "이 참가자의 완료가 유효한가"를 뜻한다)
  bool get wasMyEvidenceDisputed => me.decision == 'dispute';
  bool get wasOpponentEvidenceDisputed => opponent.decision == 'dispute';

  // 내가 상대를 판정했지만 상대가 아직 나를 판정하지 않아 결과가 안 나온 상태(속도전에서 특히 중요).
  bool get isAwaitingOpponentDecision =>
      battle.status == 'judging' && me.evidenceSubmittedAt != null && me.decision == null;
  ```
- 결과 사유 문구 선택은 위 getter 조합으로 화면에서 결정한다(승/패 자체는 서버가 정한 `winner_id`만 읽는다):
  - 승리 + `wasOpponentEvidenceDisputed` → "이의제기로 이김", 그 외 승리 → "먼저 증명해서 이김"
  - 패배 + `wasMyEvidenceDisputed` → "내 증거 무효로 짐", 그 외 패배 → "상대가 먼저 증명함"

### 신규 provider

```dart
final evidencePhotoUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, path) {
  return ref.watch(battleRepositoryProvider).createEvidencePhotoUrl(path);
});
```

### `pubspec.yaml` 변경
`image_picker` 패키지를 추가한다(사진 촬영/갤러리 선택). 이 프로젝트에 사진 선택 관련 기존 패키지가 없음을 확인함 — 추가 사유는 커밋 메시지에 "품질전 사진 증거 필수화 + 속도전 증거 제출에 사진 선택 UI 필요"로 남긴다(CLAUDE.md 코딩 규칙).

## CLAUDE.md 갱신 필요

이번 설계로 "도메인 규칙" 섹션의 아래 항목들은 문구 자체가 사실과 맞지 않게 된다. 실제 파일 수정은 구현 단계(plan.md/커밋)에서 하되, 바뀔 문구를 여기 명시해둔다.

- 기존: `속도전 판정: 서버 타임스탬프(completed_at)가 빠른 쪽 승. 클라이언트 시간을 신뢰하지 않는다.`
  → 변경: `속도전 판정: 완료 주장 시 증거(사진 또는 텍스트 중 최소 하나) 제출이 필수이고, 양쪽 참가자가 각자 제출한 뒤 서로의 증거를 approve/dispute해야 결과가 확정된다. 이의제기는 그 참가자의 완료를 무효화한다 — 양쪽 다 승인이면 evidence_submitted_at이 이른 쪽 승리, 한쪽만 승인이면 제출이 늦었더라도 승인받은 쪽 승리, 양쪽 다 이의제기면 유효한 완료가 없어 승자 없이 disputed. 클라이언트 시간을 신뢰하지 않는다.`
- 기존: `품질전 판정: 완료 시 증거(사진 또는 텍스트) 제출 → 상대가 approve / dispute 선택. approve 시 종료.`
  → 변경: `품질전 판정: 완료 시 증거(사진 필수, 텍스트만으로는 불가) 제출 → 상대가 approve / dispute 선택. 양쪽 다 approve면 finished, 하나라도 dispute면 disputed.`
- 기존: `dispute 상태의 대결은 MVP에서 "미결" 상태로 남긴다. AI 심판은 나중에 붙인다.`
  → 변경: `disputed로 끝난 대결은 MVP에서 "미결"(승자 없음)로 남긴다. AI 심판은 나중에 붙인다. 단, 속도전에서 한쪽만 이의제기당한 경우는 disputed가 아니라 상대 승리로 종결된다.`
- 기존: `대결 상태 전이: pending(모집 중, 상대 없음) → active(참가자가 매칭됨) → judging(품질전만) → finished | disputed | cancelled`
  → 변경: `대결 상태 전이: pending(모집 중, 상대 없음) → active(참가자가 매칭됨) → judging(증거 제출 후 상호 판정 대기 — 속도전/품질전 모두 거침) → finished | disputed | cancelled`

## TODO_BACKLOG.md 갱신 필요

`TODO_BACKLOG.md`의 "품질전 증거 사진 업로드 — ... Storage 버킷/RLS + image_picker 필요" 항목은 이번 스코프로 승격되어 이번 작업으로 구현되므로, 구현 완료 시 해당 줄을 제거한다.

## 결정 필요

없음.

(이전 버전에서 남겼던 "이의제기당한 참가자의 증거 재제출 허용 여부"는 사용자 확인을 거쳐 spec.md 결정 9번으로 확정됐다: **재제출은 이의제기 이후든 판정 전이든 항상 허용하고, 판정(`decision`)을 리셋하며 제출 시각(`evidence_submitted_at`)도 갱신한다.** 실수로 잘못된 증거를 올린 경우를 복구할 수 있게 하되, 제출 시각이 밀리므로 "대충 빨리 내고 이의제기당하면 그때 제대로 낸다"는 전략이 이득이 되지 않는다.

이 동작은 기존 `submit_quality_evidence`와 동일하므로 위 `submit_evidence` SQL에 **추가 가드가 필요 없다** — 위에 실어둔 SQL이 그대로 확정본이다. 다만 재제출로 승부 기준 시각이 바뀌는 경로는 판정 테스트 케이스로 반드시 검증돼야 하므로, 위 "판정 테스트 케이스" 표에 다음 케이스를 추가한다: *"속도전에서 먼저 제출한 A가 이의제기당한 뒤 재제출하면, A의 제출 시각이 갱신되어 B보다 늦어지고, 이후 양쪽 다 승인되면 B가 승리한다."*)
