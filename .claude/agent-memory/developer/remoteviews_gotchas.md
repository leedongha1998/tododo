---
name: remoteviews-gotchas
description: RemoteViews(홈 화면 위젯)로 그릴 때의 함정 — 취소선은 StrikethroughSpan만 되고 setPaintFlags 반사는 위젯을 깨뜨리며, 항목을 걸러 그릴 때 줄 슬롯 번호와 항목 index를 겹쳐 쓰면 빈 줄이 남는다
metadata:
  type: reference
---

홈 화면 위젯(`TodoWidgetProvider`)을 그리는 쪽의 함정. **네이티브는 유닛 테스트를 두지 않으므로
실기기에서만 드러난다** — 고치기 전에 여기를 먼저 볼 것. (패키지 쪽 배관 함정은
[[home-widget-package-gotchas]].)

1. **취소선은 `SpannableString` + `StrikethroughSpan`을 `setTextViewText`로 보낸다.**
   `views.setInt(id, "setPaintFlags", …)`를 **쓰지 말 것** — RemoteViews의 반사 호출은 대상 메서드가
   `@RemotableViewMethod`여야 하고 `TextView.setPaintFlags(int)`에는 그 표시가 없다. **컴파일은
   통과하고 적용 시점에 위젯 전체가 "문제가 발생했습니다"로 떨어진다**(가장 비싼 실패 방식).
   `StrikethroughSpan`은 `ParcelableSpan`이라 런처 프로세스로 파셀을 타고 넘어가 되살아난다.
   실기기에서 선이 안 그어지면 **취소선만 포기**하고 면·글자색·채워진 칸으로 구별한다(미리 정한 폴백).
2. **그림 크기와 터치 영역을 나누려면 `background`가 아니라 `src`를 쓴다.** `background`에 shape를
   걸고 뷰를 키우면 **뷰 전체가 칠해진다**. `src` + 패딩이면 그림은 content box, 터치는 뷰 전체다.
   shape는 고유 크기가 없어 `src`로 쓰면 content box를 채운다.
3. **항목을 걸러 그릴 때 줄 슬롯 번호와 항목 index를 겹쳐 쓰지 말 것.** 걸러진 항목 자리에 빈 줄이
   남는다. 루프는 항목 배열을 돌면서 `rowIndex`를 **따로** 세고, 남은 슬롯을 `GONE`으로 접는다.
4. 쓸 수 있는 변경은 **`setTextViewText`·`setTextColor`·`setViewVisibility`·`setImageViewResource`·
   `setInt(id, "setBackgroundResource", …)`** 수준이다(마지막 것은 `@RemotableViewMethod`라 안전).
   **"안 건드리면 XML 기본값"은 거짓이다.** 매 그리기가 새 `RemoteViews` 객체이긴 하지만 런처는
   레이아웃이 같으면 **`reapply()`로 기존 뷰 위에 덧칠**하므로 앞서 칠한 값이 그대로 남는다.
   그래서 **특수 상태(완료 줄 등)를 칠했으면 평소 상태도 `else`에서 반드시 되돌려 칠해야 한다.**
   2026-11-19에 이것으로 버그가 났다: 완료 줄만 칠하고 미완료를 안 되돌려서, 되돌리기(완료 해제)
   뒤에 **취소선만 지워지고 면·체크 그림이 완료 모양으로 남았다**(제목은 `setTextViewText`를 늘
   다시 해서 지워진 것이다). 같은 함정이 **줄 슬롯 재사용 전반**에 걸린다 — 그 자리에 다른 할 일이
   들어와도 앞 항목의 칠이 남는다.
5. `paddingHorizontal`/`paddingVertical`은 **API 26부터**다. 이 앱의 `minSdk`는 24이므로 네 방향을
   따로 적는다.
6. 레이아웃 기본값으로 쓸 한국어는 생성기(`tool/generate_widget_resources.dart`)가 `AppStrings`에서
   뽑아 `widget_resources.xml`로 떨군다. **캐시로 전달할 수 없는 자리**(캐시가 없을 때·옛 캐시·위젯
   선택기 미리보기)만 그렇게 하고, 나머지 문구는 전부 캐시 JSON으로 간다.
