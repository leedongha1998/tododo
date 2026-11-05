package com.todododo.todododo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 홈 화면 투두 위젯을 그린다.
 *
 * 이 파일은 **그리기만** 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을
 * 어떻게 적는지는 전부 Dart가 정해 기기 캐시(JSON 한 개)에 적어 둔다
 * (lib/features/todo/data/todo_widget_payload.dart). 여기서 하는 판단은 둘뿐이다:
 *   1. 이 높이에 몇 줄이 들어가나([rowCountFor])
 *   2. 캐시가 준 서식에 숫자 하나 끼우기("그 외 %d개")
 * 그 둘 외의 규칙을 이 파일에 더하지 말 것 — 네이티브는 테스트하지 않으므로, 판단이 늘어나면
 * 검증되지 않는 코드가 늘어난다(design 원칙 2).
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

    // 위젯의 어느 곳을 눌러도 앱이 열린다. 체크 칸만 6단계에서 자기 PendingIntent를 갖는다
    // (자식에 건 것이 부모보다 앞선다). MainActivity를 명시적으로 지목하므로 manifest에
    // 새 intent-filter가 필요 없다.
    views.setOnClickPendingIntent(
        R.id.widget_root,
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(LAUNCH_URI)),
    )

    val payload = readPayload(widgetData)
    if (payload == null) {
      // 캐시가 아직 없거나(설치 직후) 판 번호를 모를 때. 빈 사각형을 보여 주지 않는다.
      showCenter(views, context.getString(R.string.todo_widget_no_cache))
      appWidgetManager.updateAppWidget(appWidgetId, views)
      return
    }

    val centerText = payload.text("centerText")
    var drawnRows = 0
    if (centerText.isNotEmpty()) {
      showCenter(views, centerText)
    } else {
      drawnRows =
          showRows(views, payload, rowCountFor(appWidgetManager.getAppWidgetOptions(appWidgetId)))
    }
    val note = showNote(context, views, payload)

    // 마지막 방어선: 그릴 것이 하나도 없으면 반드시 대체 문구로 떨어진다(design 6.3). 어떤
    // 캐시를 읽어도 빈 사각형이 홈 화면에 남지 않게 한다.
    if (centerText.isEmpty() && drawnRows == 0 && !note) {
      showCenter(views, context.getString(R.string.todo_widget_no_cache))
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

  private fun showCenter(views: RemoteViews, text: String) {
    views.setViewVisibility(R.id.widget_rows, View.GONE)
    views.setViewVisibility(R.id.widget_center, View.VISIBLE)
    views.setTextViewText(R.id.widget_center, text)
  }

  /** 그린 줄 수를 돌려준다("그 외 N개" 줄도 한 줄로 센다). */
  private fun showRows(views: RemoteViews, payload: JSONObject, rowCount: Int): Int {
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

      val isPending = pendingFresh && item.text("id") == pendingId
      views.setViewVisibility(CHECK_IDS[index], if (isPending) View.GONE else View.VISIBLE)
      views.setViewVisibility(PENDING_IDS[index], if (isPending) View.VISIBLE else View.GONE)
      if (isPending) {
        views.setTextViewText(PENDING_IDS[index], pendingLabel)
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

  /** note를 그렸는지 돌려준다. */
  private fun showNote(context: Context, views: RemoteViews, payload: JSONObject): Boolean {
    val note = payload.text("note")
    if (note.isEmpty()) {
      views.setViewVisibility(R.id.widget_note, View.GONE)
      return false
    }
    views.setViewVisibility(R.id.widget_note, View.VISIBLE)
    views.setTextViewText(R.id.widget_note, note)
    val color =
        if (payload.text("noteTone", "muted") == "danger") R.color.widget_danger
        else R.color.widget_ink_muted
    views.setTextColor(R.id.widget_note, context.getColor(color))
    return true
  }

  /**
   * 위젯 높이(dp) → 그릴 줄 수. 줄 높이 36dp, note 20dp 기준이다(design 6.2).
   *
   * 런처가 높이를 알려 주지 않으면(0) 선언한 최소 높이(110dp)로 본다.
   */
  private fun rowCountFor(options: Bundle): Int {
    val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
    val height = if (minHeight <= 0) DEFAULT_MIN_HEIGHT_DP else minHeight
    return when {
      height < 80 -> 1
      height < 120 -> 2
      height < 180 -> 3
      height < 250 -> 5
      else -> MAX_ROWS
    }
  }

  private companion object {
    /** Dart가 쓰고 네이티브가 읽는 캐시 키. 바꾸면 todo_widget_host.dart도 함께 바꿔야 한다. */
    const val PAYLOAD_KEY = "todo_widget_payload"

    /** todoWidgetSchemaVersion과 같은 값이어야 한다. */
    const val SCHEMA_VERSION = 1

    const val PENDING_TIMEOUT_MS = 60_000L
    const val DEFAULT_MIN_HEIGHT_DP = 110
    const val MAX_ROWS = 6

    /** todo_widget_payload.dart의 widgetTargetOf가 해석하는 Uri. */
    const val LAUNCH_URI = "todododo://widget/todo"

    val ROW_IDS =
        intArrayOf(
            R.id.widget_row_0,
            R.id.widget_row_1,
            R.id.widget_row_2,
            R.id.widget_row_3,
            R.id.widget_row_4,
            R.id.widget_row_5,
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
