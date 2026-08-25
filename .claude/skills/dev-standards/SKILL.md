---
name: dev-standards
description: 코딩·테스트 컨벤션 — 코드베이스에서 추출한 초안, 검토 필요 항목 표시됨
---

# 개발 컨벤션 (코드베이스 분석 초안)

아래는 기존 코드에서 관찰한 컨벤션을 정리한 것이다. 근거 파일을 각 항목에 달아뒀다.
`[검토 필요]`가 붙은 항목은 관찰 사례가 적거나 해석의 여지가 있어 확신이 낮다 — 프로젝트 오너가 확정할 것.

## 디렉터리/패키지 구조
- `lib/features/<feature>/{data,domain,presentation}/` 3분할. CLAUDE.md에 이미 명시된 규칙과 일치.
  (근거: `lib/features/battle/{data,domain,presentation}`, `lib/features/todo/{data,domain,presentation}`)
- `data/`: Supabase row ↔ Dart 모델 변환(`fromMap` 팩토리) + Repository 클래스.
  (근거: `lib/features/battle/data/battle.dart`, `lib/features/battle/data/battle_repository.dart`)
- `domain/`: Riverpod provider, 화면에 필요한 조합 모델(예: `BattleDetail`, `BattleSummary`).
  (근거: `lib/features/todo/domain/todo_providers.dart`, `lib/features/battle/domain/battle_summary.dart`)
- `presentation/`: `ConsumerWidget`/`ConsumerStatefulWidget` 화면.
  (근거: `lib/features/todo/presentation/todo_list_screen.dart`)

## 네이밍
- 파일명: snake_case, 클래스명과 1:1 대응 (`battle_repository.dart` → `BattleRepository`).
- Provider 변수명: `<대상><역할>Provider` 형태, camelCase (`todosProvider`, `battleRepositoryProvider`, `openRecruitsProvider`).
  (근거: `lib/features/todo/domain/todo_providers.dart:7-14`, `lib/features/battle/domain/battle_providers.dart`)
- Repository 메서드명: 동사+명사, DB 동작을 그대로 반영 (`fetchTodos`, `addTodo`, `setDone`, `joinBattle`, `cancelBattle`).
  (근거: `lib/features/battle/data/battle_repository.dart`)
- 모델의 DB 컬럼명(snake_case) ↔ Dart 필드명(camelCase) 매핑은 `fromMap`에서만 처리하고, 그 외 계층은 camelCase만 사용한다.
  (근거: `lib/features/battle/data/battle.dart:26-38`)

## 상태 관리 (Riverpod)
- 데이터 조회는 `FutureProvider`, DB 클라이언트 주입은 `Provider`.
  (근거: `lib/features/todo/domain/todo_providers.dart`)
- 쓰기 작업 후에는 `ref.invalidate(...)`로 관련 provider를 무효화해 목록을 갱신한다. 상태를 수동으로 patch하지 않는다.
  (근거: `lib/features/battle/presentation/create_battle_screen.dart:33-34`, `lib/features/todo/presentation/todo_list_screen.dart:57-58`)
- 화면은 `AsyncValue.when(data:, loading:, error:)`으로 분기한다.
  (근거: `lib/features/todo/presentation/todo_list_screen.dart:141-177`)

## 에러 처리
- 모든 쓰기 작업은 `try/catch`로 감싸고, catch에서 `debugPrint('<동작명> failed: $e')`로 로그를 남긴 뒤
  `if (mounted)`/`if (context.mounted)` 체크 후 `ScaffoldMessenger.showSnackBar`로 사용자에게 알린다.
  CLAUDE.md의 "에러는 삼키지 않는다" 규칙과 일치하며, 이 패턴이 표준으로 보인다.
  (근거: `lib/features/todo/presentation/todo_list_screen.dart:59-63,76-79,86-89,96-99`,
  `lib/features/battle/presentation/create_battle_screen.dart:38-40`)
- `AsyncValue`의 `error` 분기에서도 동일하게 `debugPrint`로 로그를 남긴다.
  (근거: `lib/features/todo/presentation/todo_list_screen.dart:174-177`)
- [검토 필요] 에러 메시지 문자열은 항목별로 별도 정의(`saveTodoFailed`, `deleteTodoFailed`, `battleRecruitSubmitFailed`)하는지,
  공통 메시지 하나로 묶어도 되는지 — 지금까지는 케이스별로 나뉘어 있다(근거: `lib/core/strings.dart`).

## 문자열
- 사용자에게 보이는 모든 문자열은 `lib/core/strings.dart`의 `AppStrings` 클래스 static const로 정의.
  CLAUDE.md 규칙과 일치. (근거: `lib/core/strings.dart`)
- 다이얼로그/스낵바 등에서 즉석 한글 리터럴을 쓰는 경우도 일부 있다(예: 테스트 코드의 목 데이터 제목).
  [검토 필요] presentation 코드 안에서도 즉석 리터럴이 허용되는 범위 — 지금 관찰로는 `AppStrings`가 원칙,
  테스트 픽스처 데이터는 예외로 보인다.

## Supabase 접근
- RPC 호출은 판정/상태 전이가 걸린 동작(참가, 취소, 완료, 증거 제출/판정)에 사용하고,
  단순 CRUD(개인 투두)는 `_client.from(table)`을 직접 사용한다.
  CLAUDE.md "판정 로직은 DB(RLS/트리거) 또는 Edge Function에서" 규칙과 일치.
  (근거: `lib/features/battle/data/battle_repository.dart:52-58,81-98` vs `lib/features/todo/data/todo_repository.dart`)
- Repository는 생성자 주입(`BattleRepository(this._client)`)이며 `SupabaseClient`를 직접 받는다. 싱글턴 접근(`supabase` 전역)은 provider 레이어에서만 사용.
  (근거: `lib/features/todo/domain/todo_providers.dart:7-9` vs `lib/features/battle/data/battle_repository.dart:6-9`)

## 테스트
- 위젯 테스트는 `test/widget_test.dart` 하나에 몰려 있다(기존 관찰 유지, 화면별 파일 분리 없음).
- 도메인 로직(판정, 상태 전이) 유닛 테스트는 `test/features/<feature>/domain/<file>_test.dart`로
  lib 구조를 그대로 미러링한다. `BattleDetail`(상태 전이 판단 getter)과 `BattleRecord.fromBattle`
  (결과 라벨 판정)에 대한 예시가 있다.
  (근거: `test/features/battle/domain/battle_detail_test.dart`, `test/features/profile/domain/battle_record_test.dart`)
- 위젯/화면(`presentation/`)에 상태 전이 조건(`status == 'active' && ...` 등)을 직접 쓰지 않는다.
  domain 모델(`BattleDetail` 등)에 명명된 getter로 올려서, 위젯은 그 getter만 읽고 로직은 유닛 테스트로 검증한다.
  (근거: `lib/features/battle/domain/battle_detail.dart`의 `canCompleteSpeedTask` 등,
  `lib/features/battle/presentation/battle_detail_screen.dart`에서의 사용)
- [검토 필요] 실제 판정/상태 전이 강제(트리거·RLS)는 `supabase/migrations/*.sql`에 있고, 이는 로컬 Postgres가
  없어(Docker 미설치) 아직 유닛 테스트할 수 없다. Docker 설치 후 pgTAP 등으로 SQL 레벨 테스트를 추가할 것 —
  현재는 Dart 쪽에서 파생되는 상태 해석 로직만 테스트 가능하다.
- Repository를 목(mock)할 때는 `implements <RepositoryClass>`로 페이크 클래스를 만들고 Riverpod `overrideWith*`로 주입한다.
  별도 mocking 프레임워크(mockito 등)는 쓰지 않는다.
  (근거: `test/widget_test.dart:26-65`)
- 위젯 테스트 이름은 한글 문장으로, 검증하려는 사용자 시나리오를 그대로 서술한다.
  (근거: `test/widget_test.dart` 각 `testWidgets` 첫 인자)

## 커밋 메시지
- `<type>: <한글 설명>` 형식. type은 `feat`, `fix`, `docs`, `chore` 관찰됨.
  (근거: `git log --oneline`: `fix: 대결 모집 등록 후...`, `feat: 대결 생성을...`, `docs: CLAUDE.md...`, `chore: supabase CLI...`)
- 설명은 대결/도메인 용어를 그대로 사용해 무엇이 바뀌었는지 요약한다(예: "대결 생성을 상대 지목 초대에서 주제 모집으로 변경").
- CLAUDE.md 규칙("새 화면 하나 = 새 커밋 하나")과 일치하는 패턴으로 보인다 — 커밋 단위가 화면/기능 단위로 나뉘어 있음.

## 빌드/린트
- 정적 분석: `flutter analyze` (설정: `analysis_options.yaml`, `package:flutter_lints/flutter.yaml` 포함).
- 커스텀 린트 규칙 추가 없음 — flutter_lints 기본값 그대로 사용 중.
- 포맷터: `dart format` (Flutter 표준, 별도 설정 파일 없음).
- [검토 필요] pre-commit/CI 린트 강제 장치는 현재 저장소에 없다 — developer 에이전트의 PostToolUse 훅이 사실상 첫 자동 강제가 된다.
