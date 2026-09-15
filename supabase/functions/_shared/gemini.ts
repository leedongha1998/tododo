// Gemini 호출은 여기 한 곳에서만 한다. 모델명도 여기에만 있다.
//
// 키(GEMINI_API_KEY)는 Edge Function 환경변수로만 읽는다. 코드·로그·응답 어디에도 값을 남기지 않는다.
// 무료 등급 모델이 바뀌면 시크릿 GEMINI_MODEL만 바꾼다(코드 배포 없이).

/// 2026-09 기준 무료 등급에서 이미지 입력과 구조화 출력을 지원하는 Flash 계열.
const DEFAULT_MODEL = 'gemini-2.5-flash';

export const geminiModel = Deno.env.get('GEMINI_MODEL') ?? DEFAULT_MODEL;

/// AI 호출이 실패한 이유. 어떤 이유든 호출자에게는 "AI 실패"로 같게 취급된다
/// (기준 생성은 하루 10회에 세지 않고, 속도전은 그 제출만 무효, 품질전은 재시도).
export type GeminiFailure =
  | 'CONFIG'
  | 'HTTP'
  | 'TIMEOUT'
  | 'NETWORK'
  | 'BLOCKED'
  | 'EMPTY'
  | 'PARSE';

export class GeminiError extends Error {
  constructor(message: string, readonly failure: GeminiFailure) {
    super(message);
    this.name = 'GeminiError';
  }
}

export interface GeminiJsonRequest {
  /// 역할과 규칙. 사용자 유래 텍스트를 여기에 넣지 않는다.
  systemInstruction: string;
  /// 판정 대상 데이터. 태그로 감싼 사용자 입력이 들어간다.
  userText: string;
  /// 구조화 출력 스키마. 서버가 응답을 한 번 더 검증한다(이것만 믿지 않는다).
  responseSchema: unknown;
  /// 사진(선택). 5·6단계 판정에서 쓴다.
  images?: { mimeType: string; dataBase64: string }[];
  timeoutMs?: number;
}

/// 구조화 JSON 응답을 받아 파싱해 돌려준다. 실패는 전부 GeminiError다.
export async function generateJson(request: GeminiJsonRequest): Promise<unknown> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  if (!apiKey) {
    throw new GeminiError('GEMINI_API_KEY가 설정되지 않았습니다.', 'CONFIG');
  }

  const parts: unknown[] = [{ text: request.userText }];
  for (const image of request.images ?? []) {
    parts.push({ inline_data: { mime_type: image.mimeType, data: image.dataBase64 } });
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), request.timeoutMs ?? 30_000);

  let response: Response;
  try {
    response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          // 키는 헤더로만 보낸다. URL에 넣으면 로그에 남을 수 있다.
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: request.systemInstruction }] },
          contents: [{ role: 'user', parts }],
          generationConfig: {
            temperature: 0,
            responseMimeType: 'application/json',
            responseSchema: request.responseSchema,
          },
        }),
        signal: controller.signal,
      },
    );
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new GeminiError('Gemini 호출이 시간 안에 끝나지 않았습니다.', 'TIMEOUT');
    }
    throw new GeminiError('Gemini에 연결하지 못했습니다.', 'NETWORK');
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    // 상태 코드만 남긴다. 본문에 키가 섞여 돌아올 이유는 없지만 통째로 로그하지 않는다.
    throw new GeminiError(`Gemini 응답 상태 ${response.status}`, 'HTTP');
  }

  const body = await response.json().catch(() => null) as {
    candidates?: { finishReason?: string; content?: { parts?: { text?: string }[] } }[];
  } | null;

  const candidate = body?.candidates?.[0];
  if (!candidate) {
    throw new GeminiError('Gemini가 후보를 돌려주지 않았습니다.', 'EMPTY');
  }
  // 안전 차단(finishReason != STOP)도 실패로 본다(프롬프트 원칙 6).
  if (candidate.finishReason && candidate.finishReason !== 'STOP') {
    throw new GeminiError(`Gemini 응답이 중단됐습니다: ${candidate.finishReason}`, 'BLOCKED');
  }

  const text = (candidate.content?.parts ?? []).map((part) => part.text ?? '').join('');
  if (!text.trim()) {
    throw new GeminiError('Gemini 응답이 비어 있습니다.', 'EMPTY');
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new GeminiError('Gemini 응답이 JSON이 아닙니다.', 'PARSE');
  }
}
