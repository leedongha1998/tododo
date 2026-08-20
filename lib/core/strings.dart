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
  static const delete = '삭제';
  static const emptyTodos = '아직 할 일이 없어요.\n오른쪽 아래 버튼으로 추가해보세요.';
  static const loadTodosFailed = '할 일을 불러오지 못했습니다.';
  static const saveTodoFailed = '저장에 실패했습니다. 다시 시도해주세요.';
  static const deleteTodoFailed = '삭제에 실패했습니다. 다시 시도해주세요.';

  static const battleCreate = '대결 만들기';
  static const battleTypeSpeed = '속도전';
  static const battleTypeQuality = '품질전';
  static const battleTitleHint = '무엇을 걸고 대결할까요?';
  static const battleTitleRequired = '대결 내용을 입력해주세요.';
  static const battleRecruitSubmit = '모집 등록하기';
  static const battleRecruitSubmitted = '모집을 등록했습니다.';
  static const battleRecruitSubmitFailed = '모집 등록에 실패했습니다. 다시 시도해주세요.';

  static const battleRecruits = '모집함';
  static const battleOpenRecruits = '모집 중인 대결';
  static const battleMyRecruits = '내가 등록한 모집';
  static const battleJoin = '참가하기';
  static const battleJoined = '매칭되어 대결이 시작됐습니다.';
  static const battleJoinFailed = '참가에 실패했습니다. 다시 시도해주세요.';
  static const battleRecruitsEmpty = '모집 중인 대결이 없어요.';
  static const battleLoadRecruitsFailed = '모집 목록을 불러오지 못했습니다.';
  static const battleRecruitCancel = '취소';
  static const battleRecruitCancelled = '모집을 취소했습니다.';
  static const battleRecruitCancelFailed = '취소에 실패했습니다. 다시 시도해주세요.';

  static const battleMyBattles = '내 대결';
  static const battleMyBattlesEmpty = '진행 중인 대결이 없어요.';
  static const battleLoadListFailed = '대결 목록을 불러오지 못했습니다.';
  static const battleLoadDetailFailed = '대결 정보를 불러오지 못했습니다.';
  static const battleStatusActive = '진행중';
  static const battleStatusJudging = '판정중';
  static const battleStatusFinished = '종료';
  static const battleStatusDisputed = '미결';

  static const battleMe = '나';
  static const battleOpponent = '상대';
  static const battleComplete = '완료하기';
  static const battleCompleted = '완료했습니다.';
  static const battleCompleteFailed = '완료 처리에 실패했습니다. 다시 시도해주세요.';
  static const battleSpeedDone = '완료함';
  static const battleSpeedWaiting = '진행중';
  static const battleSpeedWaitingOpponent = '상대방을 기다리는 중이에요.';
  static const battleYouWon = '승리했습니다!';
  static const battleYouLost = '아쉽지만 패배했어요.';

  static const battleEvidenceHint = '완료했다는 증거를 남겨주세요';
  static const battleEvidenceSubmit = '증거 제출하기';
  static const battleEvidenceSubmitted = '증거를 제출했습니다.';
  static const battleEvidenceSubmitFailed = '증거 제출에 실패했습니다. 다시 시도해주세요.';
  static const battleEvidenceWaitingSubmit = '아직 증거를 제출하지 않았어요.';
  static const battleEvidenceWaitingOpponentSubmit = '상대방의 증거 제출을 기다리는 중이에요.';
  static const battleEvidenceReview = '상대방이 제출한 증거';
  static const battleApprove = '승인';
  static const battleDispute = '이의제기';
  static const battleDecisionFailed = '판정에 실패했습니다. 다시 시도해주세요.';
  static const battleDecisionWaiting = '상대방의 판정을 기다리는 중이에요.';
  static const battleDecisionApproved = '상대방이 승인했어요.';
  static const battleQualityFinished = '모두 승인되어 대결이 종료됐어요.';
  static const battleDisputedMessage = '이의제기가 있어 아직 미결 상태예요.';

  static const profileTitle = '프로필';
  static const profileLoadFailed = '프로필을 불러오지 못했습니다.';
  static const profileRecordEmpty = '아직 완료된 대결이 없어요.';
  static const profileLoadRecordFailed = '전적을 불러오지 못했습니다.';
  static const battleRecordWin = '승';
  static const battleRecordLose = '패';
}
