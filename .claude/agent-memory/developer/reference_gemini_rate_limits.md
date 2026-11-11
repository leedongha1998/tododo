---
name: reference-gemini-rate-limits
description: Gemini 무료 등급의 모델별 RPM/RPD 숫자는 공식 문서에서 사라졌고 AI Studio 로그인 페이지에만 있다(2026-11-11 확인)
metadata:
  type: reference
---

`https://ai.google.dev/gemini-api/docs/rate-limits`는 **`https://aistudio.google.com/docs/rate-limits`로
리다이렉트**되고, 그 문서에는 **모델별 무료 등급 숫자(RPM/TPM/RPD) 표가 더 이상 없다.** 대신
"Rate limits … can be viewed in Google AI Studio" + `https://aistudio.google.com/rate-limit` 버튼만 있다
(로그인 필요 → **오너만 볼 수 있다**).

문서에서 확인할 수 있는 것은 성질뿐이다:
- "Rate limits are applied **per project**, not per API key" / RPD는 태평양시 자정에 리셋.
- "Limits **vary depending on the specific model** being used" → 한도는 모델별이고, 교차 모델 집계
  풀은 문서에 없다(Batch·Priority만 별도 경로이고 그것도 모델별).
- 남아 있는 모델별 표는 Batch API 절뿐인데 거기서도 `Gemini Embedding`이 Flash 계열과 별개 행이다.

**How to apply**: 한도 숫자가 필요한 판단(예: 임베딩이 생성 모델의 RPD를 깎는지)은 문서로 끝낼 수
없다. 성질까지는 문서로 적고 **숫자 확인은 오너에게 넘긴다**(AI Studio의 rate-limit 페이지 한 번
보기). 문서에 없는 숫자를 추측해 적으면 틀린 값이 근거로 굳는다.

곁에서 확인된 임베딩 사실(`aistudio.google.com/docs/embeddings`):
- `gemini-embedding-001`은 여전히 제공되고 `taskType`(`SEMANTIC_SIMILARITY` 등)을 받는다.
  **후속 `gemini-embedding-2`는 taskType을 받지 않는다**(프롬프트에 문장으로 쓰라고 한다).
- `gemini-embedding-001`은 **3072가 아닌 차원(768 등)을 정규화해 주지 않는다 → 직접 L2 정규화**해야
  한다. `gemini-embedding-2`는 자동으로 해 준다.

관련: [[sql_shared_value_space]] (criteria-cache 작업에서 함께 쓴 교차 검산), `docs/specs/criteria-cache/plan.md`
"## 요청 한도 풀 확인".
