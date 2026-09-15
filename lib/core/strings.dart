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
  static const battleTitleRequired = '대결 내용을 입력해주세요.';
  static const battleRecruitSubmit = '모집 등록하기';
  static const battleRecruitSubmitted = '모집을 등록했습니다.';
  static const battleRecruitSubmitFailed = '모집 등록에 실패했습니다. 다시 시도해주세요.';

  static const todoTitle = '할 일';
  static const battleFind = '대결 찾기';
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
  static const battleDuration1Day = '1일';
  static const battleDuration3Days = '3일';
  static const battleDuration7Days = '7일';
  static const battleDurationNotice = '마감은 상대가 매칭되는 순간부터 시작돼요.';
  static const battleDeadlineLabel = '마감';
  static const battleDeadlinePassed = '마감이 지났어요. 곧 결과가 정리돼요.';
  static const battleDrawMessage = '시간 안에 끝내지 못해 무승부로 끝났어요.';
  static String battleDeadlineLeft(String remaining) => '$remaining 남음';

  static const battleVersus = 'vs';
  static const battleMe = '나';
  static const battleOpponent = '상대';
  static const vsIntroVersus = 'VS';
  // 화면 읽기 사용자에게 인트로를 한 번에 읽어 준다.
  static String vsIntroSemantics(String me, String opponent) => '$me 대 $opponent';
  static const battleYouWon = '승리했습니다!';
  static const battleYouLost = '아쉽지만 패배했어요.';

  static const battleEvidencePhotoLoadFailed = '사진을 불러오지 못했어요.';

  // 사진 제출과 AI 판정이 붙기 전까지 대결 상세의 제출 자리에 두는 안내(ai-judge 1단계).
  static const battleSubmissionPreparingTitle = '사진 제출 준비 중';
  static const battleSubmissionPreparing = '앱 카메라로 찍은 사진을 AI 심판이 판정하는 기능을 준비하고 있어요.';
  static const battleVoidedMessage = 'AI 판정이 계속 실패해 무효가 됐어요. 점수·전적에 반영되지 않아요.';

  static const battleForfeit = '대결 포기';
  static const battleForfeitConfirmTitle = '대결을 포기할까요?';
  // 속도전·품질전 모두 포기한 쪽이 지고 상대가 이긴다.
  static const battleForfeitConfirm = '포기하면 패배로 끝나고 3점이 깎여요. 상대가 승리해요.';
  static const battleForfeitDone = '대결을 포기했습니다.';
  static const battleForfeitFailed = '포기에 실패했습니다. 다시 시도해주세요.';
  static const battleLostByForfeit = '내가 기권해서 졌어요.';
  static const battleWonByForfeit = '상대가 기권해서 이겼어요.';

  static const profileTitle = '프로필';
  static const profileLoadFailed = '프로필을 불러오지 못했습니다.';
  static const profileRecordEmpty = '아직 완료된 대결이 없어요.';
  static const profileLoadRecordFailed = '전적을 불러오지 못했습니다.';
  static const profileRecordSection = '전적';
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
