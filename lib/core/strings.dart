class AppStrings {
  AppStrings._();

  static const appName = '투두두두';

  static const googleSignIn = '구글로 로그인';
  static const signInFailed = '로그인에 실패했습니다. 다시 시도해주세요.';
  static const supabaseNotConfigured = 'Supabase 설정이 필요합니다.\n--dart-define으로 SUPABASE_URL / SUPABASE_ANON_KEY를 전달해주세요.';

  static const logout = '로그아웃';
  static const addTodo = '할 일 추가';
  static const editTodo = '할 일 수정';
  static const todoInputHint = '할 일을 입력하세요';
  static const save = '저장';
  static const cancel = '취소';
  static const retry = '다시 시도';
  static const loading = '불러오는 중';
  static const delete = '삭제';
  static const emptyTodos = '아직 할 일이 없어요.\n오른쪽 아래 버튼으로 추가해보세요.';
  static const loadTodosFailed = '할 일을 불러오지 못했습니다.';
  static const saveTodoFailed = '저장에 실패했습니다. 다시 시도해주세요.';
  static const deleteTodoFailed = '삭제에 실패했습니다. 다시 시도해주세요.';

  static const battleCreate = '대결 만들기';
  static const battleTypeSpeed = '속도전';
  static const battleTypeQuality = '품질전';
  static const battleTitleHint = '무엇을 걸고 대결할까요?';
  static const battleRecruitSubmitted = '모집을 등록했습니다.';

  static const todoTitle = '할 일';
  static const battleFind = '대결 찾기';
  static const battleOpenRecruits = '모집 중인 대결';
  static const battleMyRecruits = '내가 등록한 모집';
  static const battleJoined = '매칭되어 대결이 시작됐습니다.';
  static const battleRecruitsEmpty = '모집 중인 대결이 없어요.';
  static const battleLoadRecruitsFailed = '모집 목록을 불러오지 못했습니다.';
  static const battleRecruitCancel = '취소';
  static const battleRecruitCancelled = '모집을 취소했습니다.';
  static const battleRecruitCancelFailed = '취소에 실패했습니다. 다시 시도해주세요.';

  static const battleMyBattles = '내 대결';
  static const battleMyBattlesEmpty = '진행 중인 대결이 없어요.';
  static const battleFinishedInProfile = '지난 대결은 프로필에서 볼 수 있어요.';
  static const battleLoadListFailed = '대결 목록을 불러오지 못했습니다.';
  static const battleLoadDetailFailed = '대결 정보를 불러오지 못했습니다.';
  static const battleStatusActive = '진행중';
  static const battleStatusJudging = '판정중';
  static const battleStatusFinished = '종료';
  static const battleStatusDisputed = '미결';
  static const battleStatusDraw = '무승부';
  static const battleStatusVoided = '무효';

  static const battleDuration = '기간';
  // 기간은 분 단위 커스텀이라 라벨을 고정 상수로 덮을 수 없다. 떨어지는 가장 큰 단위로 말한다.
  static String battleDurationDays(int days) => '$days일';
  static String battleDurationHours(int hours) => '$hours시간';
  static String battleDurationMinutes(int minutes) => '$minutes분';
  static const battleDurationCustom = '직접 입력';
  static const battleDurationQuick = '자주 쓰는 기간';
  static const battleDurationUnitMinute = '분';
  static const battleDurationUnitHour = '시간';
  static const battleDurationUnitDay = '일';
  static const battleDurationHint = '숫자';
  static const battleDurationRequired = '기간을 정해 주세요.';
  static const battleDurationOutOfRange = '1분에서 7일 사이로 정해 주세요.';
  static const battleDurationNotice = '마감은 상대가 매칭되는 순간부터 시작돼요.';
  static const battleDurationShortWarning = '짧은 기간을 고르면 매칭 알림을 놓쳤을 때 손도 못 대고 질 수 있어요.';
  static const battleDurationWindowNotice = '기간은 사진을 내는 시간이고, 마감 뒤 24시간 동안 서로 판정해요.';
  static const battleDeadlineLabel = '마감';
  static const battleDeadlinePassed = '마감이 지났어요. 곧 결과가 정리돼요.';
  // 속도전 아무도 통과 못함(마감 또는 양쪽 판정 소진), 품질전 제출 없음·둘 다 기준 미달.
  // 마감 전에 끝나는 경우도 있어서 "시간이 다 됐다"로만 말하지 않는다.
  static const battleDrawMessage = '승부를 가를 기준 통과가 없어 무승부로 끝났어요.';
  static String battleDeadlineLeft(String remaining) => '$remaining 남음';

  // 내 대결 목록의 상태 한 줄. 푸시가 없는 MVP에서 "알림 대상 사건"을 앱 안에서 확인하는 자리다.
  static const battleListSettling = '마감됨 · 판정 마무리 중';
  // mutual-judge: judging은 이제 AI가 아니라 참가자 상호 판정 창이다. 두 유형 공통.
  static const battleListJudging = '서로 판정하는 중이에요';
  static const battleListOpponentSubmitted = '상대가 제출했어요';

  static const battleVersus = 'vs';
  static const battleMe = '나';
  static const battleOpponent = '상대';
  static const vsIntroVersus = 'VS';
  // 화면 읽기 사용자에게 인트로를 한 번에 읽어 준다.
  static String vsIntroSemantics(String me, String opponent) => '$me 대 $opponent';
  static const battleYouWon = '승리했습니다!';
  static const battleYouLost = '아쉽지만 패배했어요.';
  // 결과 배너 부제와 점수 변화. 값은 전부 서버가 정해 둔 것을 옮긴다.
  static const battleCompletedLoss = '기준은 통과했지만 상대가 먼저 통과했어요.';
  static const battleWonByOpponentNoShow = '상대가 제출하지 않아 승리했어요.';
  static const battleVerdictReasonLabel = 'AI 판정 사유';
  static const battleScoreChangeLabel = '점수 변화';
  static String battleScoreDelta(int delta) => delta > 0 ? '+$delta점' : '$delta점';
  static const battleScoreFloorNote = '점수는 0점 아래로 내려가지 않아요.';

  static const battleEvidencePhotoLoadFailed = '사진을 불러오지 못했어요.';

  // 증거 사진 제출. 증거는 앱 카메라로 찍은 사진만이다(갤러리 경로 없음).
  // mutual-judge: 제출 즉시 AI가 판정하지 않는다. 판정은 마감(또는 양쪽 제출) 뒤 상호 판정 창에서
  // 일어나고, 그 화면은 4단계에서 만든다 — 여기서는 제출·교체만 다룬다.
  static const battleEvidenceSectionTitle = '내 증거';
  static const battleEvidenceTakePhoto = '사진 찍기';
  static const battleEvidenceRetake = '다시 찍기';
  static const battleEvidenceSubmit = '제출';
  static const battleEvidenceUploading = '사진을 올리고 있어요';
  static const battleEvidenceSubmitting = '제출하고 있어요';
  static const battleEvidenceHistoryTitle = '내 제출 이력';
  // 종결 뒤에는 양쪽 제출이 사진·사유와 함께 열린다(진행 중에는 서버가 상대 행을 주지 않는다).
  static const battleEvidenceNoSubmission = '제출한 사진이 없어요.';
  static const battleEvidenceCaptureFailed = '사진을 찍지 못했어요. 다시 시도해주세요.';
  static const battleEvidenceSubmitFailed = '제출에 실패했습니다. 다시 시도해주세요.';
  // 속도전: 상대가 아직 내지 않은 동안에만 교체할 수 있다. 교체하면 제출 시각이 다시 찍힌다.
  static const battleEvidenceSubmittedWaitingOpponent =
      '제출했어요. 상대가 제출하기 전까지 사진을 바꿀 수 있어요.';
  static const battleEvidenceReplace = '사진 바꾸기';
  static const battleEvidenceReplaceHint =
      '상대가 제출하기 전까지 바꿀 수 있어요. 바꾸면 제출 시각이 다시 기록돼요.';
  // 상대 영역. 진행 중에는 사진도 제출 시각도 보여 주지 않는다(서버도 내주지 않는다) — "제출했다"는
  // 사실 하나만 보인다.
  static const battleEvidenceOpponentTitle = '상대 제출';
  static const battleEvidenceOpponentWaiting = '아직 제출 전';
  static const battleEvidenceOpponentSubmitted = '제출했어요';

  // 품질전 제출. 한 번만 낼 수 있고 재제출 수단이 없어서 제출 전에 반드시 확인받는다(결정 14).
  static const battleEvidenceQualityOnce = '품질전은 한 번만 낼 수 있어요. 기간 안에 더 완벽하게 해낸 사람이 이겨요.';
  static const battleEvidenceQualitySubmit = '제출 (한 번만 가능)';
  static const battleEvidenceQualityConfirmTitle = '이 사진으로 제출할까요?';
  static const battleEvidenceQualityConfirm = '품질전은 한 번만 낼 수 있어요. 제출한 뒤에는 다시 찍을 수 없어요.';
  static const battleEvidenceQualitySubmittedTitle = '제출 완료';
  static const battleEvidenceQualityWaiting = '상대가 제출하면 판정이 시작돼요.';
  // 판정 창(judging). 속도전·품질전 공통. 실제 판정 화면은 4단계에서 만든다.
  static const battleJudgingPlaceholderTitle = '판정 창이 열렸어요';
  static const battleJudgingPlaceholder = '서로 판정하면 결과가 나와요. 판정 화면은 곧 추가돼요.';
  static const battleVoidedMessage = 'AI 판정이 계속 실패해 무효가 됐어요. 점수·전적에 반영되지 않아요.';

  static const battleForfeit = '대결 포기';
  static const battleForfeitConfirmTitle = '대결을 포기할까요?';
  // 속도전·품질전 모두 포기한 쪽이 지고 상대가 이긴다.
  static const battleForfeitConfirm = '포기하면 패배로 끝나고 3점이 깎여요. 상대가 승리해요.';
  static const battleForfeitDone = '대결을 포기했습니다.';
  static const battleForfeitFailed = '포기에 실패했습니다. 다시 시도해주세요.';
  static const battleLostByForfeit = '내가 기권해서 졌어요.';
  static const battleWonByForfeit = '상대가 기권해서 이겼어요.';

  // AI 데이터 제공 동의(제3자 제공·국외 이전). 항목 문구는 decisions.md 48·69번 기준.
  static const aiConsentTitle = 'AI 데이터 제공 동의';
  static const aiConsentIntro = '대결 결과는 AI 심판이 판정해요. 이를 위해 아래 정보를 해외 AI 사업자에게 제공해요.';
  static const aiConsentDetailsTitle = '제공 내용';
  static const aiConsentRecipientLabel = '받는 자';
  static const aiConsentRecipient = 'Google LLC (미국)';
  static const aiConsentItemsLabel = '제공 항목';
  static const aiConsentItems = '대결 제목, 판정 기준(품질전은 우열 기준 포함), 증거 사진';
  static const aiConsentPurposeLabel = '이용 목적';
  static const aiConsentPurpose = 'AI 판정. Google이 자사 서비스 개선에 쓰거나 사람이 검토할 수 있어요.';
  static const aiConsentRetentionLabel = '보유 기간';
  static const aiConsentRetention = 'Google 정책에 따름';
  static const aiConsentRefusalLabel = '거부할 권리';
  static const aiConsentRefusal =
      '동의하지 않을 수 있어요. 동의하지 않으면 대결을 만들거나 참가할 수 없고, 할 일 기능은 그대로 쓸 수 있어요.';
  static const aiConsentPrivacyPolicy = '개인정보처리방침';
  static const aiConsentAgree = '동의하고 계속';
  static const aiConsentDisagree = '동의하지 않음';
  static const aiConsentRequired = '동의해야 대결에 참여할 수 있어요.';
  static const aiConsentGiveFailed = '동의를 저장하지 못했습니다. 다시 시도해주세요.';
  static const aiConsentLoadFailed = '동의 상태를 불러오지 못했습니다.';
  static const aiConsentSection = 'AI 데이터 제공 동의';
  static String aiConsentStatusGiven(String date) => '동의함 ($date)';
  static const aiConsentStatusNotGiven = '동의 안 함';
  static const aiConsentGive = '동의하기';
  static const aiConsentWithdraw = '동의 철회';
  static const aiConsentWithdrawConfirmTitle = '동의를 철회할까요?';
  static String aiConsentWithdrawImpact(int active, int pending) =>
      '진행 중인 대결 $active개는 모두 포기(패배, -3점) 처리되고 모집 중인 대결 $pending개는 취소돼요.';
  static const aiConsentWithdrawAfter = '다시 동의하기 전까지 대결을 만들거나 참가할 수 없어요.';
  static const aiConsentWithdrawImpactFailed = '진행 중인 대결을 확인하지 못했어요. 잠시 후 다시 시도해주세요.';
  static const aiConsentWithdrawConfirm = '철회하기';
  static const aiConsentWithdrawDone = '동의를 철회했습니다.';
  static const aiConsentWithdrawFailed = '동의 철회에 실패했습니다. 다시 시도해주세요.';

  // AI 판정 기준(생성·수정·차단).
  static const battleCriteriaGenerate = 'AI 기준 만들기';
  static const battleCriteriaGenerating = 'AI가 판정 기준을 만들고 있어요';
  static const battleCriteriaGeneratingDetail = '최대 30초 정도 걸려요';
  static const battleCriteriaMinTitle = '최소 기준';
  static const battleCriteriaMinHint = '이걸 모두 만족하면 통과예요';
  static const battleCriteriaSuperiorityTitle = '우열 기준';
  static const battleCriteriaSuperiorityHint = '둘 다 통과하면 이걸로 승자를 가려요';
  static const battleCriteriaEdit = '수정';
  static const battleCriteriaSubmit = '이 기준으로 올리기';
  static const battleCriteriaRecheck = '다시 검사하기(1회 차감)';
  static const battleCriteriaRevert = '원래 기준으로 되돌리기';
  static const battleCriteriaBlocked = '사진으로 증명할 수 없는 미션이라 대결로 만들 수 없어요';
  static const battleCriteriaFixTitle = '제목 고치기';
  static const battleCriteriaAdd = '기준 추가';
  static const battleCriteriaRemove = '기준 삭제';
  static String battleCriteriaCallsLeft(int left) => '오늘 남은 기준 생성 $left/10회';
  static const battleCriteriaTooFew = '기준은 최소 1개가 필요해요.';
  static const battleCriteriaTooMany = '기준은 최대 5개까지예요.';
  static const battleCriteriaItemEmpty = '비어 있는 기준이 있어요.';
  static const battleCriteriaItemTooLong = '기준 하나는 100자까지 쓸 수 있어요.';
  static const battleCriteriaEditRecruit = '기준 수정';
  static const battleCriteriaApply = '기준 바꾸기';
  static const battleCriteriaApplied = '기준을 바꿨습니다.';

  // 모집 상세 시트와 전적 카드.
  static const battleRecruitJoinWithCriteria = '이 기준으로 참가';
  static const battleTypeSpeedTagline = '기준을 먼저 통과한 사람이 이겨요';
  static const battleTypeQualityTagline = '기간 안에 더 완벽하게 해낸 사람이 이겨요';
  static const battleRecruitCreatorLabel = '만든 사람';
  static const battleCriteriaChanged = '생성자가 기준을 바꿨어요. 바뀐 기준을 확인한 뒤 참가해 주세요.';
  static String playerScoreLabel(int score) => '$score점';
  static String playerRecordLabel(int wins, int losses, int draws) => '$wins승 $losses패 $draws무';
  static const playerStatsUnknown = '전적 없음';

  // 서버 오류 코드별 문구. 서버 메시지를 그대로 보여 주지 않는다.
  static const battleErrorAlreadyMatched = '이미 다른 사람이 참가했어요.';
  static const battleErrorCreatorDailyLimit = '모집한 사람이 오늘 대결 한도를 다 썼어요. 내일 다시 시도해주세요.\n'
      '(유료 사용자는 더 할 수 있게 될 예정이에요)';
  static const battleErrorPendingExists = '모집 중인 대결은 한 번에 1개만 올릴 수 있어요.';
  static const battleErrorDailyLimit = '오늘은 이미 대결을 했어요. 지금은 하루에 한 번 대결할 수 있어요.\n'
      '(유료 사용자는 더 할 수 있게 될 예정이에요)';
  static const battleErrorCriteriaCallLimit = '오늘 기준 만들기 횟수를 다 썼어요. 내일 다시 시도해주세요.';
  static const battleErrorCheckInvalid = '기준 확인이 만료됐어요. 기준을 다시 만들어 주세요.';
  static const battleErrorNotPending = '이미 매칭되어 기준을 바꿀 수 없어요.';
  static const battleErrorAiFailed = 'AI가 응답하지 않았어요. 잠시 후 다시 시도해 주세요.\n'
      '(횟수는 차감되지 않았어요)';
  static const battleErrorCapturedBeforeStart = '대결이 시작되기 전에 찍은 사진은 낼 수 없어요.';
  static const battleErrorCaptureTimeMismatch = '찍은 지 10분이 지난 사진이에요. 다시 찍어 주세요.';
  static const battleErrorDeadlinePassed = '마감이 지나 제출할 수 없어요.';
  // mutual-judge: 상대가 이미 제출해 교체 불가 / 품질전 이미 제출 / 판정 창 열림, 세 경우를 함께 가리킨다.
  static const battleErrorSubmissionLocked = '상대가 이미 제출해서 바꿀 수 없어요.';
  static const battleErrorUnknown = '요청을 처리하지 못했습니다. 다시 시도해주세요.';

  static const profileTitle = '프로필';
  static const profileLoadFailed = '프로필을 불러오지 못했습니다.';
  static const profileRecordEmpty = '아직 완료된 대결이 없어요.';
  static const profileLoadRecordFailed = '전적을 불러오지 못했습니다.';
  static const profileRecordSection = '전적';
  static const profileLoadStatsFailed = '점수를 불러오지 못했습니다.';
  // 무효는 점수에도 승/패/무에도 들어가지 않는다. 목록에만 남아 숫자와 어긋나 보이므로 이유를 적는다.
  static const profileVoidedExcluded = '무효 대결은 점수와 승/패/무에 넣지 않아요.';
  static const profileHistorySection = '지난 대결';
  static const battleRecordWin = '승';
  static const battleRecordLose = '패';
  static const battleRecordDraw = '무';
  // AI 판정 실패로 끝난 대결. 내 기록에만 보이고 승/패/무 집계에 들어가지 않는다.
  static const battleRecordVoided = '무효';

  static const accountSection = '계정';
  static const openSourceLicenses = '오픈소스 라이선스';
  static const accountDelete = '계정 삭제';
  static const accountDeleteConfirmTitle = '정말 계정을 삭제할까요?';
  static const accountDeleteConfirmMessage = '할 일, 증거 사진, 표시 이름이 모두 삭제되고 되돌릴 수 없어요.\n'
      '진행 중인 대결은 승자 없이 취소되고, 이미 끝난 대결 기록에는 "탈퇴한 사용자"로 남습니다.';
  static const accountDeleteConfirm = '삭제하기';
  static const accountDeleteDone = '계정을 삭제했습니다.';
  static const accountDeleteFailed = '계정 삭제에 실패했습니다. 다시 시도해주세요.';
}
