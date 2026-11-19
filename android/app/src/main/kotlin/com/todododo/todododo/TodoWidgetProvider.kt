package com.todododo.todododo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.text.Spannable
import android.text.SpannableString
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

/**
 * 홈 화면 투두 위젯을 그린다.
 *
 * 이 파일은 **그리기만** 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을
 * 어떻게 적는지는 전부 Dart가 정해 기기 캐시(JSON 한 개)에 적어 둔다
 * (lib/features/todo/data/todo_widget_payload.dart). 여기서 하는 판단은 **여섯**이고 전부
 * "비교하고 Dart가 보내 준 것 중에서 고르기"다(design 원칙 2의 2026-11-18 각주 둘):
 *   1. 이 높이에 몇 줄이 들어가나([rowCountFor])
 *   2. 캐시가 준 서식에 숫자 하나 끼우기("그 외 %d개")
 *   3. `now - pendingAtMs < 60초`인가(`쓰는 중`을 그릴지)
 *   4. `now >= dueAtMs`인가(기한 줄의 문장·색 고르기 — [showDue])
 *   5. `rank < limit`인가(이 항목을 그릴지 — 줄 자리 수는 런처가 주는 높이에서 나와 Dart가
 *      모르므로, Dart가 **순서만 숫자로 굳혀** 보내고 여기서 비교 한 줄을 한다)
 *   6. `done`인가(줄 면·제목 색·취소선·체크 그림 고르기 — 사실은 Dart가 적어 보낸다)
 * 그 여섯 외의 규칙을 이 파일에 더하지 말 것, 특히 **문장을 만들지 말 것** — 네이티브는
 * 테스트하지 않으므로 판단이 늘어나면 검증되지 않는 코드가 늘어난다(design 원칙 2).
 * 머리 줄의 개수(`할 일 2/5`)도 **완성된 문장**으로 실려 오므로 여기서 숫자를 세지 않는다.
 *
 * 주기 갱신(30분, res/xml/todo_widget_info.xml)이 하는 일도 "캐시를 다시 읽어 그리기"뿐이다.
 * 서버를 부르지 않고 Dart를 깨우지 않는다.
 */
class TodoWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { id -> render(context, appWidgetManager, id, widgetData) }
  }

  /** 사용자가 위젯 크기를 바꾼 직후에도 줄 수가 따라오게 한다. */
  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: Bundle,
  ) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
  }

  private fun render(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      widgetData: SharedPreferences,
  ) {
    val views = RemoteViews(context.packageName, R.layout.todo_widget)

    // 위젯의 어느 곳을 눌러도 앱이 열린다. 체크 칸만 자기 PendingIntent를 갖는다
    // (자식에 건 것이 부모보다 앞선다). MainActivity를 명시적으로 지목하므로 manifest에
    // 새 intent-filter가 필요 없다.
    val launch =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(LAUNCH_URI))
    views.setOnClickPendingIntent(R.id.widget_root, launch)
    // 제목+기한을 감싼 칸에 **한 번** 건다(design 4.5). 제목 TextView·기한 TextView에 따로 걸지
    // 않는 이유는 기한 줄을 눌러도 같은 결과여야 하기 때문이고, 체크 칸 바로 옆 1px부터 앱 열기가
    // 되도록 경계를 또렷하게 두려는 것이다. 줄이 GONE이어도 걸어 두는 것은 무해하다.
    for (id in TEXT_IDS) {
      views.setOnClickPendingIntent(id, launch)
    }

    val payload = readPayload(widgetData)
    // **머리 줄은 캐시를 읽기 전에, 어떤 갈래에서도 반드시 다시 쓴다.** 안 쓰고 넘어가면 앞서 쓴
    // 값이 남는다(`reapply`, showRow의 주석 참고) — 로그아웃 캐시에서 가운데가 `로그인이
    // 필요해요`인데 머리 줄만 **직전 사용자의 `할 일 2/5`**로 남는 사고가 난다.
    showHeader(context, views, payload)

    if (payload == null) {
      // 캐시가 아직 없거나(설치 직후) 판 번호를 모를 때. 빈 사각형을 보여 주지 않는다.
      showCenter(context, views, context.getString(R.string.todo_widget_no_cache))
      appWidgetManager.updateAppWidget(appWidgetId, views)
      return
    }

    val centerText = payload.text("centerText")
    var drawnRows = 0
    if (centerText.isNotEmpty()) {
      // 가운데 안내에도 톤을 적용한다 — `체크하지 못했어요`가 직전 목록 없이 이 자리에 뜰 때
      // 실패색으로 보여야 "실패를 삼키지 않는다"가 그 갈래에서도 성립한다(design 4.5 (3)).
      showCenter(context, views, centerText, payload.isDanger())
    } else {
      drawnRows =
          showRows(
              context,
              views,
              payload,
              rowCountFor(appWidgetManager.getAppWidgetOptions(appWidgetId)),
          )
    }
    val note = showNote(context, views, payload)

    // 마지막 방어선: 그릴 것이 하나도 없으면 반드시 대체 문구로 떨어진다(design 6.3). 어떤
    // 캐시를 읽어도 빈 사각형이 홈 화면에 남지 않게 한다.
    if (centerText.isEmpty() && drawnRows == 0 && !note) {
      showCenter(context, views, context.getString(R.string.todo_widget_no_cache))
    }

    appWidgetManager.updateAppWidget(appWidgetId, views)
  }

  /**
   * 문자열 하나를 안전하게 읽는다.
   *
   * 안드로이드(AOSP)의 `org.json`은 upstream과 달라 **값이 명시적 null이면 fallback이 아니라
   * `"null"` 네 글자**를 돌려준다(fallback은 키가 아예 없을 때만 쓰인다). Dart는 null인 키를 애초에
   * 싣지 않지만(todo_widget_payload.dart의 `toJson`), 한쪽이 바뀌어도 깨지지 않게 여기서도 막는다.
   */
  private fun JSONObject.text(name: String, fallback: String = ""): String {
    if (isNull(name)) return fallback
    return optString(name, fallback)
  }

  private fun readPayload(widgetData: SharedPreferences): JSONObject? {
    val raw = widgetData.getString(PAYLOAD_KEY, null) ?: return null
    val json =
        try {
          JSONObject(raw)
        } catch (error: Exception) {
          null
        }
    return json?.takeIf { it.optInt("v", 0) == SCHEMA_VERSION }
  }

  /** 캐시가 `danger` 톤인가. note와 가운데 안내가 **같은 기준**으로 색을 고른다. */
  private fun JSONObject.isDanger(): Boolean = text("noteTone", "muted") == "danger"

  private fun showCenter(
      context: Context,
      views: RemoteViews,
      text: String,
      danger: Boolean = false,
  ) {
    views.setViewVisibility(R.id.widget_rows, View.GONE)
    views.setViewVisibility(R.id.widget_center, View.VISIBLE)
    views.setTextViewText(R.id.widget_center, text)
    views.setTextColor(
        R.id.widget_center,
        context.getColor(if (danger) R.color.widget_danger else R.color.widget_ink_muted),
    )
  }

  /** 그린 줄 수를 돌려준다("그 외 N개" 줄도 한 줄로 센다). */
  private fun showRows(
      context: Context,
      views: RemoteViews,
      payload: JSONObject,
      rowCount: Int,
  ): Int {
    val items = payload.optJSONArray("items")
    val itemCount = items?.length() ?: 0
    val totalCount = payload.optInt("totalCount", itemCount)

    views.setViewVisibility(R.id.widget_center, View.GONE)
    views.setViewVisibility(R.id.widget_rows, View.VISIBLE)

    // lib/features/todo/data/todo_widget_payload.dart의 visibleRows와 같은 규칙이다.
    // 그쪽이 유닛 테스트로 고정돼 있으므로 규칙을 바꿀 일이 있으면 Dart를 먼저 고친다.
    //
    // 고르는 기준은 **rank < limit 하나**다("미완료 먼저 + 방금 누른 줄 예외"는 Dart가 rank를
    // 매길 때 이미 끝났다). `그 외 N개`는 **미완료만** 세므로 limit를 줄일지도 보이는 미완료
    // 개수로 판단한다(design 6.2.2).
    var limit = if (rowCount > 0) rowCount else 0
    var moreCount = 0
    if (itemCount > 0 && rowCount > 1 && totalCount > undoneShown(items, itemCount, rowCount)) {
      limit = rowCount - 1
      moreCount = totalCount - undoneShown(items, itemCount, limit)
    }

    val pendingId = payload.text("pendingId")
    val pendingAt = payload.optLong("pendingAtMs", 0L)
    // 60초가 지난 pending은 무시한다. 쓰기 도중에 프로세스가 죽어도 "체크된 것처럼" 남지 않는다.
    val pendingFresh =
        pendingId.isNotEmpty() && System.currentTimeMillis() - pendingAt < PENDING_TIMEOUT_MS
    val pendingLabel = payload.text("pendingLabel")

    // **줄 슬롯 번호(rowIndex)와 항목 index는 같지 않다.** rank로 걸러 내므로 "배열의 3번째
    // 항목"이 "2번째 줄"에 들어갈 수 있다 — 두 번호를 겹쳐 쓰면 걸러진 항목 자리에 빈 줄이 남는다
    // (design 6.3.1이 "이번 범위에서 가장 틀리기 쉬운 한 줄"로 꼽은 자리다).
    var rowIndex = 0
    for (index in 0 until itemCount) {
      if (rowIndex >= MAX_ROWS) break
      val item = items?.optJSONObject(index) ?: continue
      if (item.rankOf(index) >= limit) continue
      showRow(context, views, rowIndex, item, pendingFresh, pendingId, pendingLabel)
      rowIndex++
    }
    for (slot in rowIndex until MAX_ROWS) {
      views.setViewVisibility(ROW_IDS[slot], View.GONE)
    }
    val shown = rowIndex

    if (moreCount > 0) {
      views.setViewVisibility(R.id.widget_more, View.VISIBLE)
      // 네이티브가 하는 유일한 문자열 조립. 서식 자체는 캐시가 준다.
      views.setTextViewText(
          R.id.widget_more,
          String.format(payload.text("moreFormat", "%d"), moreCount),
      )
    } else {
      views.setViewVisibility(R.id.widget_more, View.GONE)
    }

    return if (moreCount > 0) shown + 1 else shown
  }

  /**
   * 항목의 **줄 자리 우선순위**. `rank` 키가 없는 **옛 캐시에서는 배열 index**가 기본값이다.
   *
   * 그 기본값이 캐시 판 번호를 올리지 않아도 되게 하는 장치다(design 2.2.2): 옛 캐시는 미완료만
   * position 순서로 담겨 있으므로 `rank = index`를 주면 `rank < limit`이 옛 규칙 `take(limit)`과
   * **정확히 같아진다.** Dart의 `TodoWidgetItem.fromJson`도 같은 규칙을 쓴다.
   */
  private fun JSONObject.rankOf(index: Int): Int = optInt("rank", index)

  /** `rank < limit`로 보이게 되는 항목 중 **미완료**가 몇인가(`그 외 N개`의 기준이다). */
  private fun undoneShown(items: JSONArray?, itemCount: Int, limit: Int): Int {
    var count = 0
    for (index in 0 until itemCount) {
      val item = items?.optJSONObject(index) ?: continue
      if (item.rankOf(index) < limit && !item.isDone()) count++
    }
    return count
  }

  private fun JSONObject.isDone(): Boolean = optBoolean("done", false)

  /**
   * 줄 하나를 그린다. 완료 줄이면 **리소스 셋을 바꿔 덮는다**(뷰를 더하지 않는다):
   * 가라앉은 면 · 흐린 제목 + 취소선 · 채워진 체크 칸. 그 셋이 `쓰는 중`·성공·실패의 세 모양을
   * 구별시키는 "표시 요소의 수"다(design 4.6 (4)).
   *
   * **미완료 줄에도 그 셋을 반드시 되돌려 쓴다.** 매 그리기가 새 `RemoteViews` 객체이긴 하지만
   * 런처는 레이아웃이 같으면 **`reapply()`로 기존 뷰 위에 덧칠**하므로 레이아웃 기본값이 돌아오지
   * 않는다 — 되돌리기(완료 해제)나 그 자리에 다른 할 일이 들어온 경우 **앞서 칠한 완료 모양이
   * 그대로 남는다**. 2026-11-19 실기기에서 확인했다: 되돌린 줄의 취소선만 지워지고 면·체크 그림이
   * 완료 모양으로 남았다(제목은 `setTextViewText`를 늘 다시 해서 지워진 것이다).
   */
  private fun showRow(
      context: Context,
      views: RemoteViews,
      rowIndex: Int,
      item: JSONObject,
      pendingFresh: Boolean,
      pendingId: String,
      pendingLabel: String,
  ) {
    val done = item.isDone()
    val title = item.text("title")
    views.setViewVisibility(ROW_IDS[rowIndex], View.VISIBLE)
    views.setTextViewText(TITLE_IDS[rowIndex], if (done) struckThrough(title) else title)
    if (done) {
      views.setInt(ROW_IDS[rowIndex], "setBackgroundResource", R.drawable.widget_row_done_line)
      views.setTextColor(TITLE_IDS[rowIndex], context.getColor(R.color.widget_ink_muted))
      views.setImageViewResource(CHECK_IDS[rowIndex], R.drawable.widget_check_done)
    } else {
      views.setInt(ROW_IDS[rowIndex], "setBackgroundResource", R.drawable.widget_row_line)
      views.setTextColor(TITLE_IDS[rowIndex], context.getColor(R.color.widget_ink))
      views.setImageViewResource(CHECK_IDS[rowIndex], R.drawable.widget_check)
    }
    // 줄의 제목 색은 기한과 무관하다(지났다는 사실은 기한 줄 하나에서만 말한다 — 줄 전체를
    // 붉게 칠하면 홈 화면에서 "오류"로 읽힌다). 완료 줄에는 캐시에 기한 키가 없어 GONE이 된다.
    showDue(context, views, rowIndex, item)

    val todoId = item.text("id")
    val isPending = pendingFresh && todoId == pendingId
    views.setViewVisibility(CHECK_IDS[rowIndex], if (isPending) View.GONE else View.VISIBLE)
    views.setViewVisibility(PENDING_IDS[rowIndex], if (isPending) View.VISIBLE else View.GONE)
    if (isPending) {
      views.setTextViewText(PENDING_IDS[rowIndex], pendingLabel)
    }
    if (todoId.isNotEmpty()) {
      // 체크 칸(48x40dp)에만 백그라운드 브로드캐스트를 건다. 자식에 건 것이 부모(앱 열기)보다
      // 앞서므로 **그 사각형 안에서만** 체크가 일어나고 1px 밖은 앱 열기다.
      //
      // **줄마다 다른 PendingIntent가 되는 근거는 Uri data다.** PendingIntent의 동일성은
      // Intent.filterEquals(action·data·type·component·categories)로 따지므로 data가 다르면
      // 다른 것으로 본다. extras에 id를 싣는 방식은 쓰지 않는다 — extras는 filterEquals가 보지
      // 않아 모든 줄이 한 PendingIntent로 합쳐지고, 아무 줄을 눌러도 같은 할 일이 체크되는
      // 사고가 난다(home_widget의 getBroadcast는 요청 코드를 0으로 고정하므로 data가 유일한
      // 구분 수단이다).
      //
      // **Uri에 목표 값을 싣는다**: 미완료 줄은 `&done=1`(완료 처리), 완료 줄은 `&done=0`
      // (되돌리기). 토글이 아니라 목표 값이라 낡은 그림을 누른 탭도 사용자가 본 대로 쓰인다
      // (design 4.6 (1)). 줄마다·방향마다 data가 달라 filterEquals 구분도 그대로 성립한다.
      views.setOnClickPendingIntent(
          CHECK_IDS[rowIndex],
          HomeWidgetBackgroundIntent.getBroadcast(
              context,
              Uri.parse("$CHECK_URI_PREFIX$todoId$CHECK_URI_DONE${if (done) "0" else "1"}"),
          ),
      )
    }
  }

  /**
   * 완료 줄의 제목에 **취소선**을 입힌다. 받은 문자열에 서식을 더하는 것이고 글자를 더하거나
   * 바꾸지 않는다(원칙 2: 네이티브는 문장을 만들지 않는다).
   *
   * **`setInt(id, "setPaintFlags", …)`를 쓰지 말 것.** RemoteViews의 반사 호출은 대상 메서드가
   * `@RemotableViewMethod`여야 하고 `TextView.setPaintFlags(int)`에는 그 표시가 없다 — 컴파일은
   * 통과하고 **적용 시점에 위젯 전체가 깨진다**(design 6.1.2 (3)). `StrikethroughSpan`은
   * `ParcelableSpan`이라 런처 프로세스로 파셀을 타고 넘어가 되살아난다.
   */
  private fun struckThrough(text: String): CharSequence =
      SpannableString(text).apply {
        setSpan(StrikethroughSpan(), 0, length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
      }

  /**
   * 줄 하나의 기한 자리. 여기서 하는 판단은 **비교와 고르기**뿐이다(design 6.3):
   *   - 기한 키가 없으면 `GONE` — **대체 문구·기호를 그리지 않는다**(spec: 기한이 없는 줄에는
   *     아무것도 보이지 않는다).
   *   - `now < dueAtMs`면 `due` + widget_ink_muted.
   *   - `now >= dueAtMs`면 `dueOver` + widget_danger. 경계는 `>=`다(기한 그 시각부터 지난 것으로 본다).
   *
   * **이 비교를 네이티브에 두는 이유**: 주기 갱신은 Dart를 깨우지 않고 캐시를 다시 그리기만 하므로
   * "지났다"를 발행 시점에 굳히면 몇 시간 뒤에 **틀린 표시**가 홈 화면에 남는다. spec 수용 기준이
   * 그것을 금지했다("발행 뒤에 기한이 지난 할 일도, 위젯을 다시 그린 뒤에는 지난 것으로 보인다").
   * 문장은 둘 다 캐시가 미리 보내 주므로 여기서 문구를 만들지는 않는다.
   */
  private fun showDue(context: Context, views: RemoteViews, index: Int, item: JSONObject) {
    val dueAtMs = item.optLong("dueAtMs", 0L)
    val due = item.text("due")
    // 0은 "기한 없음"으로 다룬다(1970년을 기한으로 둔 할 일은 없다). Dart는 기한이 없는 줄에
    // 이 키를 애초에 싣지 않는다.
    if (dueAtMs <= 0L || due.isEmpty()) {
      views.setViewVisibility(DUE_IDS[index], View.GONE)
      return
    }
    val overdue = System.currentTimeMillis() >= dueAtMs
    // dueOver가 비어 있는 캐시(있을 수 없지만 방어)면 due를 쓰고 색만 바꾼다 — 빈 문자열을 그려
    // 줄이 반쯤 비는 것을 막는다.
    val text = if (overdue) item.text("dueOver", due) else due
    views.setViewVisibility(DUE_IDS[index], View.VISIBLE)
    views.setTextViewText(DUE_IDS[index], text)
    views.setTextColor(
        DUE_IDS[index],
        context.getColor(if (overdue) R.color.widget_danger else R.color.widget_ink_muted),
    )
  }

  /**
   * 머리 줄의 헤더(`할 일 2/5`). 캐시가 **완성된 문장**을 보내므로 여기서는 쓰기만 한다 —
   * 숫자를 세지도, 분수를 조립하지도 않는다(design 2.2.2).
   *
   * 캐시에 `header`가 없으면(옛 캐시·로그아웃·불러오는 중·캐시 없음) **레이아웃 기본값과 같은
   * 문자열을 직접 써 넣는다** — 개수를 모르면 말하지 않는다는 태도는 그대로이고, 다만 "안 건드리면
   * XML 기본값"에 기대지 않는다. 런처가 `reapply()`로 덧칠하므로 안 쓰고 넘어가면 **앞서 쓴 개수가
   * 그대로 남는다**(2026-11-19 확인한 함정. showRow의 주석 참고).
   */
  private fun showHeader(context: Context, views: RemoteViews, payload: JSONObject?) {
    val header = payload?.text("header").orEmpty()
    views.setTextViewText(
        R.id.widget_header,
        header.ifEmpty { context.getString(R.string.todo_widget_header) },
    )
  }

  /** note를 그렸는지 돌려준다. */
  private fun showNote(context: Context, views: RemoteViews, payload: JSONObject): Boolean {
    val note = payload.text("note")
    if (note.isEmpty()) {
      views.setViewVisibility(R.id.widget_note, View.GONE)
      return false
    }
    views.setViewVisibility(R.id.widget_note, View.VISIBLE)
    views.setTextViewText(R.id.widget_note, note)
    val color = if (payload.isDanger()) R.color.widget_danger else R.color.widget_ink_muted
    views.setTextColor(R.id.widget_note, context.getColor(color))
    return true
  }

  /**
   * 위젯 높이(dp) → 그릴 줄 수.
   *
   * lib/features/todo/data/todo_widget_payload.dart의 `widgetRowCount`와 **같은 상수로 같은 식**
   * 이다. 그쪽이 유닛 테스트로 고정돼 있으므로 수치를 바꿀 일이 있으면 Dart를 먼저 고친다
   * (design 6.2.1). 표를 하드코딩하지 않는 이유는 레이아웃 수치를 고칠 때 표를 따로 고치는 것을
   * 잊어 잘린 줄이 나오는 것을 막으려는 것이다.
   *
   * 런처가 높이를 알려 주지 않으면(0) 선언한 최소 높이(110dp)로 본다 — 그 값도 2줄 구간이다.
   */
  private fun rowCountFor(options: Bundle): Int {
    val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
    val height = if (minHeight <= 0) DEFAULT_MIN_HEIGHT_DP else minHeight
    val rows = (height - FIXED_DP) / ROW_PITCH_DP
    return rows.coerceIn(1, MAX_ROWS)
  }

  private companion object {
    /** Dart가 쓰고 네이티브가 읽는 캐시 키. 바꾸면 todo_widget_host.dart도 함께 바꿔야 한다. */
    const val PAYLOAD_KEY = "todo_widget_payload"

    /** todoWidgetSchemaVersion과 같은 값이어야 한다. */
    const val SCHEMA_VERSION = 1

    const val PENDING_TIMEOUT_MS = 60_000L
    const val DEFAULT_MIN_HEIGHT_DP = 110

    /**
     * 줄 수 공식의 상수 셋. Dart의 `todoWidgetFixedHeightDp`·`todoWidgetRowPitchDp`·
     * `todoWidgetMaxRows`와 **값이 같아야 한다**(design 6.2.1). 레이아웃(todo_widget.xml)의
     * 줄 minHeight 40dp + 아래 여백 2dp = 42dp.
     *
     * 고정비 24dp의 내역은 2026-11-18(추가 범위 2)에 바뀌었지만 **합은 그대로다**(design 6.2.2):
     * 옛 내역 = 루트 위·아래 여백 4+4 + 아래 note 16, 지금 = 루트 위·아래 여백 4+2 + 머리 줄 18.
     * 머리 줄이 옛 note의 자리를 물려받았으므로 **모든 높이에서 줄 수가 같다.**
     */
    const val FIXED_DP = 24
    const val ROW_PITCH_DP = 42
    const val MAX_ROWS = 6

    /** todo_widget_payload.dart의 widgetTargetOf가 해석하는 Uri. */
    const val LAUNCH_URI = "todododo://widget/todo"

    /**
     * 체크 칸의 Uri. 뒤에 할 일 id가 붙는다 —
     * todo_widget_payload.dart의 `todoWidgetActionOf`가 해석하는 꼴과 같아야 한다.
     */
    const val CHECK_URI_PREFIX = "todododo://widget/check?id="

    /**
     * 체크 Uri의 **목표 값** 파라미터. `1`이면 완료 처리, `0`이면 되돌리기다.
     *
     * Dart의 `todoWidgetActionOf`는 이 값이 **없거나 `0`이 아니면 완료로 읽는다** — 앱 업데이트를
     * 넘어 시스템에 남아 있는 옛 PendingIntent(이 파라미터가 없는 꼴)와 호환되기 위함이다.
     */
    const val CHECK_URI_DONE = "&done="

    val ROW_IDS =
        intArrayOf(
            R.id.widget_row_0,
            R.id.widget_row_1,
            R.id.widget_row_2,
            R.id.widget_row_3,
            R.id.widget_row_4,
            R.id.widget_row_5,
        )
    /** 제목+기한을 감싼 칸. 앱 열기 PendingIntent가 걸리는 자리다. */
    val TEXT_IDS =
        intArrayOf(
            R.id.widget_text_0,
            R.id.widget_text_1,
            R.id.widget_text_2,
            R.id.widget_text_3,
            R.id.widget_text_4,
            R.id.widget_text_5,
        )
    val TITLE_IDS =
        intArrayOf(
            R.id.widget_title_0,
            R.id.widget_title_1,
            R.id.widget_title_2,
            R.id.widget_title_3,
            R.id.widget_title_4,
            R.id.widget_title_5,
        )
    /** 제목 아래 기한 줄. 캐시에 기한 키가 있는 줄에서만 VISIBLE이 된다. */
    val DUE_IDS =
        intArrayOf(
            R.id.widget_due_0,
            R.id.widget_due_1,
            R.id.widget_due_2,
            R.id.widget_due_3,
            R.id.widget_due_4,
            R.id.widget_due_5,
        )
    val CHECK_IDS =
        intArrayOf(
            R.id.widget_check_0,
            R.id.widget_check_1,
            R.id.widget_check_2,
            R.id.widget_check_3,
            R.id.widget_check_4,
            R.id.widget_check_5,
        )
    val PENDING_IDS =
        intArrayOf(
            R.id.widget_pending_0,
            R.id.widget_pending_1,
            R.id.widget_pending_2,
            R.id.widget_pending_3,
            R.id.widget_pending_4,
            R.id.widget_pending_5,
        )
  }
}
