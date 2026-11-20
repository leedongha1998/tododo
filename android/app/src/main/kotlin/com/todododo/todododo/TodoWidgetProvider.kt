package com.todododo.todododo

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
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
 * **탭 자국 하나**(design 1.2). 이 파일이 `TAP_MARKS_KEY`에 적고 Dart는 **읽기만** 한다.
 *
 * [writing]이면 낙관 반영이 꺼진 탭이다(절전·비행기·데이터 세이버) — 그 줄은 완료 모양으로
 * 뒤집지 않고 체크 칸 자리에 `쓰는 중`을 그린다. **모드를 묶음이 아니라 자국마다 드는 이유**는
 * 모드가 바뀌는 순간에 모드가 다른 자국이 섞일 수 있고 그리기는 줄마다 결정되기 때문이다.
 */
private class TapMark(
    val gen: Int,
    val id: String,
    val done: Boolean,
    val atMs: Long,
    val writing: Boolean,
)

/**
 * **탭 자국 레코드**(design 1.2). 지금 모으는 묶음의 시각 넷과 자국 배열이다. Dart의
 * `TodoWidgetTapMarks`와 같은 모양이고, 그쪽 `todoWidgetMarksOf`가 같은 방어를 유닛 테스트로
 * 고정해 두었다.
 */
private class TapMarks(
    val gen: Int,
    val batchAtMs: Long,
    val lastAtMs: Long,
    val leaveAtMs: Long,
    val dueAtMs: Long,
    val marks: List<TapMark>,
) {
  /** 그 줄의 **가장 새 자국**. 중복 탭 판정의 입력이다(design 8.2). */
  fun latestFor(id: String): TapMark? = marks.filter { it.id == id }.maxByOrNull { it.gen }
}

/**
 * 자국들이 그리기에 주는 **겹침**(design 1.5). [render]에서 **한 번** 만들고 **네 자리**가 이것만
 * 본다 — 줄 그리기, `그 외 N개`의 기준(`undoneShown`), `totalCount` 보정, 머리 줄. **하나라도
 * 빠지면 숫자가 어긋난다**(design 6.3.3 (2) · 4.7 (5)).
 *
 * 규칙은 Dart의 순수 함수 `todoWidgetOverlayOf`에 테스트와 함께 박혀 있고(네이티브는 유닛 테스트가
 * 없다) 여기는 그것을 베낀 것이다 — **바꿀 때는 양쪽을 함께** 바꾼다.
 */
private class Overlay(
    /** 낙관으로 **뒤집어 그릴** 줄들(id → 목표 값). */
    val flips: Map<String, Boolean>,
    /** 체크 칸 자리에 `쓰는 중`을 그릴 줄들. **뒤집지 않는다.** */
    val writingIds: Set<String>,
    /** Σ(flips: 완료 +1 / 되돌리기 −1). `totalCount − doneDelta`가 보정된 미완료 개수다. */
    val doneDelta: Int,
    /** **되돌릴 시각이 지났다** — 전부 걷고 머리 줄에 이유를 적는다. */
    val lapsed: Boolean,
) {
  companion object {
    val none = Overlay(emptyMap(), emptySet(), 0, lapsed = false)
  }
}

/**
 * 홈 화면 투두 위젯을 그린다.
 *
 * 이 파일은 **그리기만** 한다. 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을
 * 어떻게 적는지는 전부 Dart가 정해 기기 캐시(JSON 한 개)에 적어 둔다
 * (lib/features/todo/data/todo_widget_payload.dart). 여기서 하는 판단은 **아홉**이고 거의 전부
 * "비교하고 Dart가 보내 준 것 중에서 고르기"다(design 원칙 2의 각주들):
 *   1. 이 높이에 몇 줄이 들어가나([rowCountFor])
 *   2. 캐시가 준 서식에 숫자 하나 끼우기("그 외 %d개")
 *   3. 그 자국이 아직 효력이 있나(60초 — `쓰는 중`을 그릴지)
 *   4. `now >= dueAtMs`인가(기한 줄의 문장·색 고르기 — [showDue])
 *   5. `rank < limit`인가(이 항목을 그릴지 — 줄 자리 수는 런처가 주는 높이에서 나와 Dart가
 *      모르므로, Dart가 **순서만 숫자로 굳혀** 보내고 여기서 비교 한 줄을 한다)
 *   6. `done`인가(줄 면·제목 색·취소선·체크 그림 고르기 — 사실은 Dart가 적어 보낸다)
 *   7. (2026-11-19) 탭 순간의 **기기 상태** → 낙관 모드인가 `쓰는 중` 모드인가([tapMode])
 *   8. (2026-11-19 · 2026-11-20에 자랐다) **자국마다** 효력이 있나(세 조건) + 묶음의 되돌림
 *      시각이 지났나([overlayOf]). 판단 3의 두 갈래가 **자국 배열 전체**로 넓어진 것이고, 규칙은
 *      Dart의 `todoWidgetOverlayOf`에 테스트와 함께 박혀 있다
 *   9. (2026-11-20) 이 탭이 **중복인가**([isDuplicateTap]) — **그 id의 가장 새 자국**과 비교
 *      셋(같은 줄·같은 목표 값·창 안쪽). Dart에 있던 판단이 **옮겨 온** 것이다: 자국을 쓰는
 *      자리가 여기라서 Dart가 읽는 자국은 언제나 이번 탭의 것이었다(그래서 모든 탭이 버려졌다).
 *      규칙 자체는 Dart의 `isDuplicateWidgetTap`에 테스트와 함께 박혀 있고 여기는 그것을 따른다
 * 그 아홉 외의 규칙을 이 파일에 더하지 말 것, 특히 **문장을 만들지 말 것** — 네이티브는
 * 테스트하지 않으므로 판단이 늘어나면 검증되지 않는 코드가 늘어난다(design 원칙 2).
 * 머리 줄의 개수(`할 일 2/5`)도 **완성된 문장**으로 실려 오므로 여기서 숫자를 세지 않는다.
 * 머리 띠의 면(평소 primary / 체크 실패 danger)도 **새 판단이 아니다** — showNote가 쓰던 그
 * 톤 비교(`isDanger()`)를 그대로 쓰고, 색 신호가 글자에서 면으로 옮겨 갔을 뿐이다(design 6.4.1).
 *
 * 주기 갱신(30분, res/xml/todo_widget_info.xml)이 하는 일도 "캐시를 다시 읽어 그리기"뿐이다.
 * 서버를 부르지 않고 Dart를 깨우지 않는다.
 *
 * **2026-11-19(추가 범위 3 J): 이 파일이 캐시를 쓰는 자리가 하나 생겼다.** 탭 순간에는 Dart가
 * 깨어 있지 않으므로(engine이 뜨는 데 1초 안쪽) 그 자리에서 즉시 그리려면 네이티브가 그려야 한다.
 *
 * **2026-11-20(추가 범위 4): 그 자리가 payload에서 떨어져 나와 별도 키가 됐다**(design 1.1).
 * 이 파일이 쓰는 것은 **[TAP_MARKS_KEY] 하나뿐**이고 payload([PAYLOAD_KEY])는 **읽기만** 한다.
 * 그래서 Dart의 발행이 자국을 건드리지 않고, **결말 하나가 아직 끝나지 않은 다른 줄의 자국을
 * 걷어 가지 않는다** — "그 묶음에 들어간 것만 걷는다"는 **지우기가 아니라 세대 비교**
 * (`g > settledGen`)로 성립한다(design 1.3·4.1). 이 소유권을 깨면(Dart가 자국 키를 쓰거나
 * 네이티브가 `settledGen`을 쓰면) 이 설계의 경합 방지가 통째로 무너진다.
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

  /**
   * 체크 칸 탭과 쓸어내기 알람을 받는다. **그 둘 말고는 전부 `super`에게 넘긴다** — 넘기지
   * 않으면 주기 갱신(APPWIDGET_UPDATE)·크기 변경·삭제가 통째로 멈추고, 증상이 "가끔 안 바뀐다"라
   * 추적이 어렵다(design 9.4의 첫 함정).
   */
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      ACTION_CHECK -> onCheckTap(context, intent.data)
      ACTION_SWEEP -> renderAll(context)
      else -> super.onReceive(context, intent)
    }
  }

  /**
   * 탭에서 결말까지의 **네이티브 구간**(design 4.7 (1)의 1~5). 목표는 0.1초, 상한 0.2초다 —
   * 여기에는 네트워크도 Dart도 없고 기기 안에서 끝나는 일만 있다.
   *
   * 순서가 중요하다:
   *   0. **기존 자국을 먼저 읽어 중복 탭을 버린다**([isDuplicateTap], 2026-11-20). 이 판정이
   *      **여기** 있어야 하는 이유는 하나다 — 탭을 처음 보는 자리도, 자국을 쓰는 자리도
   *      네이티브이기 때문이다. 자국을 쓴 뒤에 깨어나는 Dart는 **언제나 이번 탭의 자국**을 읽어
   *      중복을 가릴 수 없다(그 설계로 위젯 체크가 서버에 하나도 쓰이지 않는 회귀가 났다).
   *   1. 모드를 고른다([tapMode]) — 조건 ②(항상 실패하는 상태에서는 낙관 그림을 그리지 않는다).
   *   2. **자국을 먼저 쓰고** 3에서 그린다. 순서를 바꾸면 "그린 그림이 캐시에 없는" 순간이 생겨
   *      그 사이의 `reapply`가 그림을 되돌린다.
   *   4. 결말이 영영 오지 않아도 되돌아오게 쓸어내기 알람을 건다(탭+7초).
   *   5. **브로드캐스트 발사는 맨 뒤다.** `home_widget`은 콜백을 WorkManager로 돌리므로 그
   *      enqueue가 수십 ms를 쓸 수 있고, 그 비용이 그리기 앞에 오면 그만큼 늦게 보인다.
   *
   * 중복으로 판정한 탭은 **자국도 다시 쓰지 않고, 다시 그리지도 않고, 브로드캐스트도 쏘지 않는다**
   * — 첫 탭의 그림과 쓸어내기 시각을 흔들지 않는 것이 목적이다.
   */
  private fun onCheckTap(context: Context, data: Uri?) {
    if (data == null) return
    val todoId = data.getQueryParameter("id").orEmpty()
    if (todoId.isEmpty()) return
    // Dart의 todoWidgetActionOf와 같은 규칙이다: `0`이 아니면 완료로 읽는다(옛 PendingIntent 호환).
    val done = data.getQueryParameter("done") != "0"

    // 캐시 **두 키를 한 번씩만** 읽어 중복 판정과 자국 쓰기가 나눠 쓴다(읽기를 두 번 만들지
    // 않는다). 자국은 **별도 키**다(design 1.1) — payload와 섞지 않으므로 Dart의 발행이 자국을
    // 건드리지 않고, 결말 하나가 아직 끝나지 않은 다른 줄의 그림을 걷어 가지 않는다.
    val widgetData = HomeWidgetPlugin.getData(context)
    val payload = readPayload(widgetData)
    val marks = readMarks(widgetData)
    if (isDuplicateTap(marks, todoId, done)) return

    markTap(widgetData, payload, marks, todoId, done, tapMode(context))
    renderAll(context)
    scheduleSweep(context)
    // 패키지의 공개 API를 그대로 쓴다 — 리시버 클래스 이름·액션 문자열 같은 내부를 베껴 적으면
    // 패키지가 바뀔 때 조용히 어긋난다.
    HomeWidgetBackgroundIntent.getBroadcast(context, data).send()
  }

  /**
   * **중복 탭인가**(2026-11-20). 규칙은 Dart의 순수 함수 `isDuplicateWidgetTap`과 **같아야 한다**
   * (lib/features/todo/data/todo_widget_payload.dart). 네이티브는 유닛 테스트가 없으므로 규칙만
   * 저쪽에 뽑아 테스트로 고정해 두었다 — `ROW_PITCH_DP`·[TAP_DUP_WINDOW_MS]와 같은 방식이고,
   * **바꿀 때는 양쪽을 함께** 바꾼다.
   *
   * 셋이 모두 맞을 때만 중복이다: 같은 줄 · **같은 목표 값** · 그 자국이 [TAP_DUP_WINDOW_MS]
   * 안쪽. 보는 것은 **그 id의 가장 새 자국** 하나다(design 8.2).
   * **방향이 다른 탭(같은 줄, 다른 `done`)은 중복이 아니다** — 낙관적 반영 때문에 사용자는 이미
   * 바뀐 줄을 보고 있고, 그 줄을 다시 누르는 것은 "되돌리겠다"는 뜻이다(막으면 되돌리기가 6초
   * 동안 먹지 않는다).
   */
  private fun isDuplicateTap(marks: TapMarks?, todoId: String, done: Boolean): Boolean {
    val mark = marks?.latestFor(todoId) ?: return false
    return mark.done == done && System.currentTimeMillis() - mark.atMs < TAP_DUP_WINDOW_MS
  }

  /**
   * 자국 레코드를 **별도 키**에 적는다(design 1.2). **`apply()`가 아니라 `commit()`이다** —
   * 뒤이어 깨어나는 백그라운드 engine이 **자국이 찍힌 캐시**를 보게 하려는 것이다(design 4.7 (6)의
   * 첫 칸). 받는 자리가 `onReceive`(수 ms 작업)라 동기 쓰기의 비용이 문제 되지 않는다.
   *
   * 하는 일 넷:
   *   1. **세대**를 올린다 — `max(지금 세대, payload.settledGen) + 1`. payload가 비워졌다
   *      되살아난 경우에도 세대가 **뒤로 가지 않게** 하는 한 줄이다.
   *   2. **묶음의 시각들**을 다시 계산한다(`batchAtMs`·`lastAtMs`·`leaveAtMs`·`dueAtMs`).
   *      식은 Dart의 `widgetTapLeaveAt`·`widgetTapDueAt`과 같다(상수도 같다 — design 8.3).
   *   3. **솎아낸다** — 결말이 난 세대(`g <= settledGen`), 잊을 나이([PENDING_TIMEOUT_MS]),
   *      상한([MAX_MARKS]) 초과. 그래서 이 레코드는 자라지 않는다.
   *   4. `writing` 자국은 **묶지 않는다** — 그 상태의 사용자에게 이 기능이 주는 유일한 값이
   *      "빨리 분명해지는 실패"인데 1초를 기다리면 그마저 깎인다(spec U 조건 ②의 조임).
   *
   * 캐시를 아예 읽지 못하면(설치 직후·판 번호 모름) 아무것도 적지 않는다. 그때는 그릴 줄도 없고,
   * 깨어난 Dart가 Uri 한 줄만 쓰는 대비 경로로 간다(design 4.4의 13번).
   */
  private fun markTap(
      widgetData: SharedPreferences,
      payload: JSONObject?,
      marks: TapMarks?,
      todoId: String,
      done: Boolean,
      mode: String,
  ) {
    if (payload == null) return
    val now = System.currentTimeMillis()
    val settledGen = payload.optInt("settledGen", 0)
    val writing = mode == MODE_WRITING
    // 살아 있는 묶음이 없거나 떠날 시각이 지났으면(또는 이 탭이 writing이면) **새 묶음**이다.
    val newBatch = marks == null || now >= marks.leaveAtMs || writing
    val batchAtMs = if (newBatch) now else marks!!.batchAtMs
    val leaveAtMs = if (writing) now else leaveAtOf(batchAtMs, now)
    val gen = maxOf(marks?.gen ?: 0, settledGen) + 1
    val kept =
        (marks?.marks ?: emptyList()).filter {
          it.gen > settledGen && now - it.atMs < PENDING_TIMEOUT_MS
        }
    val next = (kept + TapMark(gen, todoId, done, now, writing)).takeLast(MAX_MARKS)

    val json = JSONObject()
    try {
      json.put("gen", gen)
      json.put("batchAtMs", batchAtMs)
      json.put("lastAtMs", now)
      json.put("leaveAtMs", leaveAtMs)
      json.put("dueAtMs", leaveAtMs + WRITE_WINDOW_MS + SETTLE_GRACE_MS)
      val array = JSONArray()
      for (mark in next) {
        val item = JSONObject()
        item.put("g", mark.gen)
        item.put("id", mark.id)
        item.put("done", mark.done)
        item.put("at", mark.atMs)
        if (mark.writing) item.put("w", true)
        array.put(item)
      }
      json.put("marks", array)
    } catch (error: Exception) {
      return
    }
    widgetData.edit().putString(TAP_MARKS_KEY, json.toString()).commit()
  }

  /**
   * **묶음이 떠날 시각** = `min(마지막 탭 + 1초, 첫 탭 + 5초)`. Dart의 `widgetTapLeaveAt`과
   * **같은 식·같은 상수**다(design 7·8.3) — 그쪽이 유닛 테스트로 고정돼 있으므로 수치를 바꿀 일이
   * 있으면 Dart를 먼저 고친다. 상한이 식 안에 있는 것이 "어느 계기도 오지 않는 경로가 없다"는
   * 보장이다.
   */
  private fun leaveAtOf(batchAtMs: Long, lastAtMs: Long): Long =
      minOf(lastAtMs + TAP_QUIET_MS, batchAtMs + TAP_BATCH_CAP_MS)

  /**
   * 자국 레코드를 되읽는다. 키가 없거나 모양이 어긋나면 **null**이다(= 자국이 없는 것으로 본다 =
   * 평소 그림). Dart의 `todoWidgetMarksOf`와 같은 방어를 하고, 그쪽이 테스트로 고정돼 있다.
   *
   * 문자열은 [text]로 읽는다 — AOSP `org.json`의 `optString`이 명시적 null에 `"null"` 네 글자를
   * 돌려주는 함정 때문이다.
   */
  private fun readMarks(widgetData: SharedPreferences): TapMarks? {
    val raw = widgetData.getString(TAP_MARKS_KEY, null) ?: return null
    val json =
        try {
          JSONObject(raw)
        } catch (error: Exception) {
          return null
        }
    val array = json.optJSONArray("marks") ?: return null
    val marks = ArrayList<TapMark>()
    for (index in 0 until array.length()) {
      val item = array.optJSONObject(index) ?: continue
      val id = item.text("id")
      if (id.isEmpty()) continue
      marks.add(
          TapMark(
              gen = item.optInt("g", 0),
              id = id,
              // 없으면 완료로 읽는다(Dart의 `todoWidgetMarksOf`와 같은 기준).
              done = item.optBoolean("done", true),
              atMs = item.optLong("at", 0L),
              writing = item.optBoolean("w", false),
          )
      )
    }
    return TapMarks(
        gen = json.optInt("gen", 0),
        batchAtMs = json.optLong("batchAtMs", 0L),
        lastAtMs = json.optLong("lastAtMs", 0L),
        leaveAtMs = json.optLong("leaveAtMs", 0L),
        dueAtMs = json.optLong("dueAtMs", 0L),
        marks = marks,
    )
  }

  /**
   * 탭 순간의 그리기 모드(판단 7). **낙관적 반영을 끄는 조건 ②가 여기에 있다.**
   *
   * 평소에는 [MODE_OPTIMISTIC]이고, **쓰기가 막힌 것이 탭 순간에 이미 드러난** 상태에서만
   * [MODE_WRITING]으로 떨어진다. 그 상태의 사용자는 "체크됨 → 풀림"을 보지 않고 `쓰는 중` →
   * 실패만 본다(spec L의 조건 ②).
   *
   * **읽기가 실패하면 낙관 쪽으로 둔다.** 조건 ②는 "항상 실패하는 상태임이 **드러난** 경우"만
   * 끄라는 것이고, 모르는 것을 실패로 단정해 모든 사용자의 체감을 깎지 않는다(design 4.7 (4)).
   */
  private fun tapMode(context: Context): String =
      try {
        if (writeBlocked(context)) MODE_WRITING else MODE_OPTIMISTIC
      } catch (error: Exception) {
        MODE_OPTIMISTIC
      }

  /**
   * 백그라운드 쓰기가 **지금 막혀 있는가.** 셋을 OR로 본다 — 전부 네트워크도 Dart도 없이 읽을 수
   * 있고, **전부 "끄는 쪽으로만" 틀린다**(네트워크가 있는데 없다고 읽거나, 종량제가 아닌데 데이터
   * 세이버로 읽는 쪽). 틀려서 켜는 경우가 없는 것이 이 묶음의 안전장치다(design 4.7 (4)).
   *
   *   1. **절전 모드**(API 21+, 권한 없음) — 안드로이드가 백그라운드 UID의 네트워크를 방화벽으로
   *      끊어서 위젯 탭이 깨우는 브로드캐스트가 DNS 단계에서 즉시 실패한다(2026-11-19 실기기
   *      확인, `TODO_BACKLOG.md`).
   *   2. **활성 네트워크가 없거나 인터넷을 못 쓴다**(API 23+, `ACCESS_NETWORK_STATE`) —
   *      비행기 모드·권외. 쓰기가 나갈 길이 없다.
   *   3. **데이터 세이버**(API 24+, 같은 권한) — **지금 기본 네트워크가 종량제일 때만** ENABLED를
   *      돌려주므로 과하게 걸리지 않는다. 그 상태의 백그라운드 쓰기는 1번과 같은 이유로 막힌다.
   *
   * 도즈(`isDeviceIdleMode`)는 **보지 않는다** — 홈 화면을 보며 탭하는 순간은 화면이 켜져 있어
   * 도즈가 아니다. 서버 응답 지연·이동 중 권외 전환 같은 **눌러 봐야 아는 실패**는 애초에 미리
   * 알 수 없고, spec 트레이드오프가 그 대가를 이미 적었다.
   */
  private fun writeBlocked(context: Context): Boolean {
    val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    if (power?.isPowerSaveMode == true) return true
    val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
    val network = connectivity.activeNetwork ?: return true
    val capabilities = connectivity.getNetworkCapabilities(network) ?: return true
    if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return true
    return connectivity.restrictBackgroundStatus ==
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
  }

  /**
   * 올라가 있는 모든 위젯을 캐시로 다시 그린다.
   *
   * **"화면에만 그리는 경로"를 만들지 않는다**(`partiallyUpdateAppWidget`을 쓰지 않는다):
   * 그려지는 것이 언제나 캐시의 함수로 남아야 다음 `reapply`·주기 갱신·크기 변경이 **같은 그림**을
   * 낸다(design 4.7 (3) 나). 비용은 JSON 하나를 읽고 파싱하는 수 ms이고, 줄이려는 것은 ms가
   * 아니라 초다.
   */
  private fun renderAll(context: Context) {
    val manager = AppWidgetManager.getInstance(context) ?: return
    val ids = manager.getAppWidgetIds(ComponentName(context, TodoWidgetProvider::class.java))
    if (ids.isEmpty()) return
    val widgetData = HomeWidgetPlugin.getData(context)
    ids.forEach { id -> render(context, manager, id, widgetData) }
  }

  /**
   * 탭+7초에 한 번 더 그리게 한다. **결말이 영영 오지 않아도 그 줄이 되돌아오고 이유가 함께
   * 보이게** 하는 장치다(design 4.7 (3) 다).
   *
   * **부정확 알람이다**(`set`은 API 19부터 inexact). `setExact`를 쓰면 `SCHEDULE_EXACT_ALARM`
   * 권한이 늘어나는데, 여기서 몇 초 늦는 것은 손해가 아니다 — 이미 끝났으면 무해한 다시 그리기이고,
   * 아예 오지 않아도 다음 그리기 계기(주기 갱신·앱 발행·크기 변경)가 결국 치운다.
   *
   * 요청 코드 고정 + `FLAG_UPDATE_CURRENT`라 **마지막 탭 하나만 남는다.**
   */
  private fun scheduleSweep(context: Context) {
    val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    val pending =
        PendingIntent.getBroadcast(
            context,
            SWEEP_REQUEST_CODE,
            Intent(context, TodoWidgetProvider::class.java).setAction(ACTION_SWEEP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    try {
      alarm.set(AlarmManager.RTC, System.currentTimeMillis() + SWEEP_DELAY_MS, pending)
    } catch (error: Exception) {
      // 알람을 걸지 못해도 탭 자체는 그대로 간다 — 위젯은 관문이 아니다.
    }
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
    val overlay = overlayOf(payload, readMarks(widgetData))
    // **"되돌림"이 보이는 유일한 계기가 쓸어내기 알람이다.** 결말이 제때 오면 세대 비교로 자국의
    // 효력이 사라지므로 이 갈래는 거의 그려지지 않는다 — 그려지는 순간은 "Dart가 끝내 답하지
    // 못했다"는 뜻이고, 그때 **되돌림(줄이 평소 모양)과 이유(이 한 줄)가 한 화면에** 나온다
    // (spec 조건 ①). 여러 줄이 함께 되돌아가도 **안내는 하나다**(spec S).
    val failNote = if (overlay.lapsed) payload?.text("failNote").orEmpty() else ""
    // **머리 줄은 캐시를 읽기 전에, 어떤 갈래에서도 반드시 다시 쓴다.** 안 쓰고 넘어가면 앞서 쓴
    // 값이 남는다(`reapply`, showRow의 주석 참고) — 로그아웃 캐시에서 가운데가 `로그인이
    // 필요해요`인데 머리 줄만 **직전 사용자의 `할 일 2/5`**로 남는 사고가 난다.
    showHeader(context, views, payload, overlay)
    // **띠 면도 같은 이유로 어떤 갈래에서든, payload == null로 일찍 돌아가기 전에 칠한다.**
    // 한쪽만 칠하면 체크 실패로 붉어진 띠가 그 뒤 성공 갈래에서도 붉게 남고(`reapply`), 캐시를
    // 못 읽는 갈래로 떨어질 때는 `앱을 한 번 열어 주세요` 위에 실패 색 띠가 뜬다(design 6.3.2 (1)).
    // 쓰는 비교는 showNote가 쓰던 isDanger() 그대로다 — 새 판단이 아니다.
    views.setInt(
        R.id.widget_header_row,
        "setBackgroundResource",
        if (payload?.isDanger() == true || failNote.isNotEmpty()) R.drawable.widget_band_danger
        else R.drawable.widget_band,
    )

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
              overlay,
          )
    }
    val note = showNote(views, payload, failNote)

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

  /**
   * 자국 배열을 **한 번** 훑어 [Overlay]를 만든다(판단 8, design 1.3·1.5). 이번 범위에서 **가장
   * 틀리기 쉬운 자리**라 규칙은 Dart의 `todoWidgetOverlayOf`에 테스트와 함께 있고 여기는 그것을
   * 베낀다 — **바꿀 때는 양쪽을 함께** 바꾼다.
   *
   * 자국은 **셋을 모두 만족할 때만** 효력이 있다:
   *   1. `g > settledGen` — 결말이 난 묶음의 자국은 효력이 없다(= 성공은 payload가 이미 그 값이고,
   *      실패는 되돌아가야 한다). 이 비교 하나가 "그 묶음에 들어간 것만 걷는다"의 전부다.
   *   2. [PENDING_TIMEOUT_MS]가 지나지 않았다 — 아무도 결말을 내지 못한 자국이 영원히 남지 않는다.
   *   3. **목표 값이 캐시의 `done`과 다르다** — 값이 이미 맞은 자국은 아무 일도 하지 않는다.
   *      이 조건이 **상쇄**를 그리기 쪽에서 공짜로 성립시킨다(같은 줄을 눌러 제자리로 돌려놓으면
   *      그 자리에서 평소 모양이다).
   *
   * 같은 줄의 자국이 여럿이면 **가장 새 것 하나만** 본다. `dueAtMs`가 지났으면 효력 있던 자국
   * **전부**를 걷고 [Overlay.lapsed]를 켠다(= 되돌림 + 머리 줄에 이유 한 줄). 효력 있는 자국이
   * 하나도 없으면 `lapsed`도 **켜지 않는다** — 상쇄만 있었던 묶음에 실패 한 줄을 띄우지 않는다.
   */
  private fun overlayOf(payload: JSONObject?, marks: TapMarks?): Overlay {
    if (payload == null || marks == null || marks.marks.isEmpty()) return Overlay.none
    val now = System.currentTimeMillis()
    val settledGen = payload.optInt("settledGen", 0)

    val doneById = HashMap<String, Boolean>()
    val items = payload.optJSONArray("items")
    for (index in 0 until (items?.length() ?: 0)) {
      val item = items?.optJSONObject(index) ?: continue
      doneById[item.text("id")] = item.isDone()
    }

    val latest = LinkedHashMap<String, TapMark>()
    for (mark in marks.marks) {
      val found = latest[mark.id]
      if (found == null || mark.gen >= found.gen) latest[mark.id] = mark
    }
    val effective =
        latest.values.filter { mark ->
          val done = doneById[mark.id]
          mark.gen > settledGen &&
              now - mark.atMs < PENDING_TIMEOUT_MS &&
              done != null &&
              done != mark.done
        }
    if (effective.isEmpty()) return Overlay.none
    if (now >= marks.dueAtMs) {
      return Overlay(emptyMap(), emptySet(), 0, lapsed = true)
    }

    val flips = HashMap<String, Boolean>()
    val writingIds = HashSet<String>()
    var doneDelta = 0
    for (mark in effective) {
      if (mark.writing) {
        writingIds.add(mark.id)
        continue
      }
      flips[mark.id] = mark.done
      doneDelta += if (mark.done) 1 else -1
    }
    return Overlay(flips, writingIds, doneDelta, lapsed = false)
  }

  /**
   * 그 줄을 **어느 쪽으로 그릴지**. 낙관 구간에만 캐시의 `done`과 달라진다.
   *
   * `isDone()`을 직접 부르던 자리를 **전부** 이 헬퍼로 바꿨다. 빠뜨리면 그림과 숫자가 어긋난다 —
   * 특히 `undoneShown`에서 빠뜨리면 **보이는 미완료만 하나 줄어 `그 외 N개`가 1 늘고**, 숨겨진
   * 할 일이 생긴 것처럼 보인다(design 6.3.3 (2)가 "가장 틀리기 쉬운 한 줄"로 꼽은 자리다).
   */
  private fun JSONObject.effectiveDone(overlay: Overlay): Boolean =
      overlay.flips[text("id")] ?: isDone()

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
      overlay: Overlay,
  ): Int {
    val items = payload.optJSONArray("items")
    val itemCount = items?.length() ?: 0
    // **낙관 구간에는 미완료 전체 개수도 함께 ∓N 한다.** 보이는 미완료가 N 줄 때 전체도 N 줄어야
    // `그 외 N개`가 그대로다 — 안 하면 숨겨진 할 일이 생긴 것처럼 보인다(design 4.7 (5) · 1.5).
    // 산수는 여전히 하나뿐이다(moreCount = totalCount − undoneShown): 그 식에 들어가는 입력
    // 하나를 옮기는 것이고 문장을 만드는 일이 아니다. **∓1이 ∓N으로 자란 자리다.**
    val totalCount =
        (payload.optInt("totalCount", itemCount) - overlay.doneDelta).coerceAtLeast(0)

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
    if (itemCount > 0 &&
        rowCount > 1 &&
        totalCount > undoneShown(items, itemCount, rowCount, overlay)) {
      limit = rowCount - 1
      moreCount = totalCount - undoneShown(items, itemCount, limit, overlay)
    }

    // `쓰는 중`은 **낙관이 꺼진 자국**의 줄에만 그린다(= 절전 모드 등. 조건 ②). 낙관이 켜져 있는
    // 줄은 이미 완료 모양이라 `쓰는 중`을 겹치지 않는다 — 모양은 셋뿐이고 네 번째를 만들지
    // 않는다. 되돌림이면 줄이 평소 모양으로 돌아가고 이유는 머리 줄이 말한다.
    val pendingLabel = payload.text("pendingLabel")

    // **줄 슬롯 번호(rowIndex)와 항목 index는 같지 않다.** rank로 걸러 내므로 "배열의 3번째
    // 항목"이 "2번째 줄"에 들어갈 수 있다 — 두 번호를 겹쳐 쓰면 걸러진 항목 자리에 빈 줄이 남는다
    // (design 6.3.1이 "이번 범위에서 가장 틀리기 쉬운 한 줄"로 꼽은 자리다).
    var rowIndex = 0
    for (index in 0 until itemCount) {
      if (rowIndex >= MAX_ROWS) break
      val item = items?.optJSONObject(index) ?: continue
      if (item.rankOf(index) >= limit) continue
      showRow(context, views, rowIndex, item, pendingLabel, overlay)
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

  /**
   * `rank < limit`로 보이게 되는 항목 중 **미완료**가 몇인가(`그 외 N개`의 기준이다).
   *
   * **낙관 구간에는 `effectiveDone`을 쓴다.** 줄만 뒤집고 여기를 안 뒤집으면 보이는 미완료가
   * 하나 줄어 `그 외 N개`가 1 늘어난다(design 6.3.3 (2)).
   */
  private fun undoneShown(
      items: JSONArray?,
      itemCount: Int,
      limit: Int,
      overlay: Overlay,
  ): Int {
    var count = 0
    for (index in 0 until itemCount) {
      val item = items?.optJSONObject(index) ?: continue
      if (item.rankOf(index) < limit && !item.effectiveDone(overlay)) count++
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
      pendingLabel: String,
      overlay: Overlay,
  ) {
    // 낙관 구간에는 **뒤집힌 값**으로 면·제목 색·취소선·체크 그림·기한·체크 Uri를 고른다.
    // 여섯 자리가 모두 이 한 값을 쓰므로 그림이 서로 어긋나지 않는다.
    val done = item.effectiveDone(overlay)
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
    showDue(context, views, rowIndex, item, done)

    val todoId = item.text("id")
    val isPending = todoId.isNotEmpty() && overlay.writingIds.contains(todoId)
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
      //
      // **2026-11-19: 탭이 우리 리시버로 먼저 들어온다**(design 4.7 (3) 가). 전에는
      // `home_widget`의 리시버로 바로 가서 우리 코드가 한 줄도 돌지 않았고, 그래서 engine이
      // 뜰 때까지 1초 넘게 화면에 아무 변화가 없었다. 이제 우리가 받아 그 자리에서 그리고
      // **그 브로드캐스트를 대신 발사한다**([onCheckTap]).
      //
      // 매니페스트에 새 `intent-filter`를 더하지 않는다 — 명시적 component Intent라 필터가
      // 필요 없고 `exported="false"`도 그대로다(우리가 만들어 런처에 넘긴 PendingIntent는
      // 우리 자격으로 발송된다). `FLAG_IMMUTABLE`은 API 31+에서 필수다.
      views.setOnClickPendingIntent(
          CHECK_IDS[rowIndex],
          PendingIntent.getBroadcast(
              context,
              0,
              Intent(context, TodoWidgetProvider::class.java)
                  .setAction(ACTION_CHECK)
                  .setData(
                      Uri.parse(
                          "$CHECK_URI_PREFIX$todoId$CHECK_URI_DONE${if (done) "0" else "1"}"
                      )
                  ),
              PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
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
  private fun showDue(
      context: Context,
      views: RemoteViews,
      index: Int,
      item: JSONObject,
      done: Boolean,
  ) {
    val dueAtMs = item.optLong("dueAtMs", 0L)
    val due = item.text("due")
    // 0은 "기한 없음"으로 다룬다(1970년을 기한으로 둔 할 일은 없다). Dart는 기한이 없는 줄에
    // 이 키를 애초에 싣지 않는다.
    //
    // [done]을 함께 보는 이유는 **낙관 구간** 하나다: 그 줄은 아직 캐시에 기한 키를 들고 있는데
    // 완료 모양으로 그려진다 → 완료 줄에 기한을 보여 주지 않는다는 규칙을 여기서 지킨다.
    // 평소에는 Dart가 캐시에서 끝내므로(완료 항목에 키를 싣지 않는다) 이 분기가 돌지 않는다.
    if (done || dueAtMs <= 0L || due.isEmpty()) {
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
  private fun showHeader(
      context: Context,
      views: RemoteViews,
      payload: JSONObject?,
      overlay: Overlay,
  ) {
    // 낙관 구간에는 **Dart가 미리 만들어 보낸 대체 문장 배열**에서 **첨자로 고른다**(design 1.4).
    // N줄이 동시에 눌리면 개수가 ∓N 움직이므로 문장 둘로는 덮지 못해 2026-11-20에 배열이 됐다.
    // 여기서 숫자를 세거나 분수를 조립하지 않는다 — 첨자를 만드는 산수(Σ)는 `totalCount` 보정과
    // 같은 종류다. 배열이 없거나 범위를 넘으면 머리 줄을 그대로 두어 개수가 결말까지 늦게
    // 맞는다("모르면 말하지 않는다").
    val delta = overlay.doneDelta
    val sentences =
        if (delta == 0) null
        else payload?.optJSONArray(if (delta > 0) "headerAfterChecks" else "headerAfterUnchecks")
    val index = (if (delta > 0) delta else -delta) - 1
    val alternate =
        if (sentences != null && index >= 0 && index < sentences.length()) {
          if (sentences.isNull(index)) "" else sentences.optString(index, "")
        } else {
          ""
        }
    val header = alternate.ifEmpty { payload?.text("header").orEmpty() }
    views.setTextViewText(
        R.id.widget_header,
        header.ifEmpty { context.getString(R.string.todo_widget_header) },
    )
  }

  /**
   * note를 그렸는지 돌려준다.
   *
   * **색을 칠하지 않는다**(2026-11-19 시안 C): note는 띠 위의 흰 글자 하나뿐이고, 실패·낡음의
   * 색 신호는 글자에서 **띠 면**으로 옮겨 갔다(render 맨 앞의 widget_band_danger. design 6.3.2 (2)).
   * 그래서 이 함수는 보이기/숨기기와 글자 넣기만 한다 — 칠하지 않으므로 reapply 함정도 없다.
   */
  private fun showNote(views: RemoteViews, payload: JSONObject, failNote: String): Boolean {
    // 자국이 지나 줄을 되돌린 경우에는 **그 이유를 캐시에서 골라** 머리 줄에 적는다 — 되돌림과
    // 설명이 같은 그리기에서 함께 나와야 한다(spec 조건 ①). 문장은 Dart가 보낸 것 그대로다.
    val note = failNote.ifEmpty { payload.text("note") }
    if (note.isEmpty()) {
      views.setViewVisibility(R.id.widget_note, View.GONE)
      return false
    }
    views.setViewVisibility(R.id.widget_note, View.VISIBLE)
    views.setTextViewText(R.id.widget_note, note)
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

    /**
     * **네이티브만 쓰는** 탭 자국 키(2026-11-20 추가 범위 4, design 1.1). Dart는 **읽기만**
     * 한다(`TodoWidgetHost.readTapMarks`). 이 소유권이 깨지면(Dart가 이 키를 쓰거나 네이티브가
     * payload의 `settledGen`을 쓰면) 읽고-고쳐-쓰기 사이에 들어온 탭이 통째로 사라진다.
     */
    const val TAP_MARKS_KEY = "todo_widget_tap_marks"

    /** todoWidgetSchemaVersion과 같은 값이어야 한다. */
    const val SCHEMA_VERSION = 1

    /**
     * 탭 자국을 **잊는** 시각. Dart의 `todoWidgetPendingTimeoutSeconds`(60초)와 **값이 같아야
     * 한다**(design 2.2.3). `ROW_PITCH_DP`와 같은 규칙이고 **테스트로 잡히지 않는다** —
     * 어긋나면 "낙관 그림이 영영 안 걷힌다"거나 "너무 일찍 걷힌다"로 나온다.
     */
    const val PENDING_TIMEOUT_MS = 60_000L

    /**
     * **중복 탭 창.** Dart의 `todoWidgetTapDupWindowMs`(6초)와 **값이 같아야 한다**(위와 같은
     * 규칙이고, 규칙 자체는 그쪽 `isDuplicateWidgetTap`이 테스트로 들고 있다).
     *
     * 2026-11-20에 **이름만** 또렷해졌다(옛 `TAP_MARK_FRESH_MS`의 값·뜻 그대로다 — 자국의
     * "신선함"이 그리기에서 떨어져 나가면서 이 창은 중복 판정에만 쓰인다). 0에 가까우면 런처의
     * 중복 전달을 막지 못하고, 길면 **같은 목표 값**의 정당한 재시도까지 막는다.
     */
    const val TAP_DUP_WINDOW_MS = 6_000L

    /**
     * **묶음의 기본 계기**(마지막 탭에서 1초)와 **상한**(첫 탭에서 5초). Dart의
     * `todoWidgetTapQuietMs`·`todoWidgetTapBatchCapMs`와 **값이 같아야 한다** — 식은 Dart의
     * `widgetTapLeaveAt`에 테스트와 함께 있고 여기 [leaveAtOf]가 그것을 베낀다(design 7·8.3).
     *
     * 어긋나면 증상이 "묶음이 떠나지 않는다"(Dart가 더 기다린다)로 나온다.
     */
    const val TAP_QUIET_MS = 1_000L
    const val TAP_BATCH_CAP_MS = 5_000L

    /**
     * 묶음이 떠난 뒤의 **쓰기 창**(5초)과 결말 발행·그리기에 주는 **여유**(1초). 되돌릴 시각은
     * `leaveAtMs + 이 둘` ≈ 마지막 탭+7초다. Dart의 `todoWidgetWriteWindowMs`·
     * `todoWidgetSettleGraceMs`와 **값이 같아야 한다**(design 7).
     *
     * 여유가 0이면 Dart의 실패 발행과 쓸어내기가 **같은 순간**에 겹쳐 그림이 두 번 바뀐다.
     */
    const val WRITE_WINDOW_MS = 5_000L
    const val SETTLE_GRACE_MS = 1_000L

    /**
     * 자국 레코드가 들고 있는 자국의 최대 개수(Dart의 `todoWidgetMaxTapMarks`와 같아야 한다).
     * 보이는 줄이 최대 6이고 되돌림까지 두 번씩 눌러도 12다. 넘으면 **오래된 것부터 버린다** —
     * 버려진 자국은 그 줄이 평소 모양으로 돌아가는 것이 전부다(거짓 성공이 아니다).
     */
    const val MAX_MARKS = 12

    /** 쓸어내기 알람까지의 시간(탭+7초). 24단계에서 **절대 시각 `dueAtMs`**로 바뀐다. */
    const val SWEEP_DELAY_MS = 7_000L

    /** 쓸어내기 PendingIntent의 요청 코드. 고정이라 **마지막 탭 하나만 남는다.** */
    const val SWEEP_REQUEST_CODE = 1

    /** 우리 리시버가 받는 액션 둘. 그 밖의 액션은 전부 `super.onReceive`로 간다. */
    const val ACTION_CHECK = "com.todododo.todododo.action.WIDGET_CHECK"
    const val ACTION_SWEEP = "com.todododo.todododo.action.WIDGET_SWEEP"

    /**
     * 탭 자국의 그리기 모드. `writing`이면 `쓰는 중`만 그리고(= 낙관 반영이 꺼진 상태),
     * `optimistic`이면 그 줄을 **완료 모양으로 미리** 그린다.
     *
     * 2026-11-20부터 모드는 **자국마다** 들고 다니고(`marks[].w`), Dart도 그 한 칸을 읽는다
     * (`TodoWidgetTapMark.writing`) — 묶음을 떠나는 시각을 그 자국이 바꾸기 때문이다(design 1.2).
     */
    const val MODE_WRITING = "writing"
    const val MODE_OPTIMISTIC = "optimistic"

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
