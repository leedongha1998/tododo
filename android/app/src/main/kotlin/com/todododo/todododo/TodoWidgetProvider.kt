package com.todododo.todododo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 홈 화면 투두 위젯을 그린다.
 *
 * 이 파일은 **그리기만** 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을
 * 어떻게 적는지는 전부 Dart가 정해 기기 캐시(JSON 한 개)에 적어 둔다
 * (lib/features/todo/data/todo_widget_payload.dart). 여기서 하는 판단은 **넷**이고 전부
 * "비교하고 Dart가 보내 준 것 중에서 고르기"다(design 원칙 2의 2026-11-18 각주):
 *   1. 이 높이에 몇 줄이 들어가나([rowCountFor])
 *   2. 캐시가 준 서식에 숫자 하나 끼우기("그 외 %d개")
 *   3. `now - pendingAtMs < 60초`인가(`쓰는 중`을 그릴지)
 *   4. `now >= dueAtMs`인가(기한 줄의 문장·색 고르기 — [showDue])
 * 그 넷 외의 규칙을 이 파일에 더하지 말 것, 특히 **문장을 만들지 말 것** — 네이티브는
 * 테스트하지 않으므로 판단이 늘어나면 검증되지 않는 코드가 늘어난다(design 원칙 2).
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

    // lib/features/todo/data/todo_widget_payload.dart의 visibleRows와 같은 규칙이다.
    // 그쪽이 유닛 테스트로 고정돼 있으므로 규칙을 바꿀 일이 있으면 Dart를 먼저 고친다.
    val shown =
        when {
          rowCount <= 0 || itemCount == 0 -> 0
          rowCount == 1 || totalCount <= rowCount -> minOf(itemCount, rowCount)
          else -> minOf(itemCount, rowCount - 1)
        }
    // `shown > 0`은 Dart의 `items.isEmpty` 조항과 같은 뜻이다. 두 언어의 규칙을 한 칸도
    // 어긋나지 않게 둔다(지금 Dart가 만드는 캐시로는 도달하지 않는 조합이지만).
    val moreCount = if (shown > 0 && rowCount > 1 && totalCount > rowCount) totalCount - shown else 0

    val pendingId = payload.text("pendingId")
    val pendingAt = payload.optLong("pendingAtMs", 0L)
    // 60초가 지난 pending은 무시한다. 쓰기 도중에 프로세스가 죽어도 "체크된 것처럼" 남지 않는다.
    val pendingFresh =
        pendingId.isNotEmpty() && System.currentTimeMillis() - pendingAt < PENDING_TIMEOUT_MS
    val pendingLabel = payload.text("pendingLabel")

    views.setViewVisibility(R.id.widget_center, View.GONE)
    views.setViewVisibility(R.id.widget_rows, View.VISIBLE)

    for (index in 0 until MAX_ROWS) {
      if (index >= shown) {
        views.setViewVisibility(ROW_IDS[index], View.GONE)
        continue
      }
      val item = items?.optJSONObject(index)
      if (item == null) {
        views.setViewVisibility(ROW_IDS[index], View.GONE)
        continue
      }
      views.setViewVisibility(ROW_IDS[index], View.VISIBLE)
      views.setTextViewText(TITLE_IDS[index], item.text("title"))
      // 줄의 제목 색은 기한과 무관하게 widget_ink다(레이아웃이 정한 그대로 둔다). 지났다는 사실은
      // 기한 줄 하나에서만 말한다 — 줄 전체를 붉게 칠하면 홈 화면에서 "오류"로 읽힌다.
      showDue(context, views, index, item)

      val todoId = item.text("id")
      val isPending = pendingFresh && todoId == pendingId
      views.setViewVisibility(CHECK_IDS[index], if (isPending) View.GONE else View.VISIBLE)
      views.setViewVisibility(PENDING_IDS[index], if (isPending) View.VISIBLE else View.GONE)
      if (isPending) {
        views.setTextViewText(PENDING_IDS[index], pendingLabel)
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
        views.setOnClickPendingIntent(
            CHECK_IDS[index],
            HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("$CHECK_URI_PREFIX$todoId"),
            ),
        )
      }
    }

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
     * 줄 minHeight 40dp + 아래 여백 2dp = 42dp, 루트 위·아래 여백 8dp + note 16dp = 24dp.
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
