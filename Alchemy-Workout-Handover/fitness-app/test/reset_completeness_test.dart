// 歸零就要真的歸零 —— 而且以後新增欄位忘了歸零，這支會失敗。
//
// [AppState.resetToNewAccount] 這個 session 已經被補過兩次：
// 第一次補上貼文、課表、歷史、訂單、對話、關係；第二次補上
// [AppState.trainedDims] 與 [AppState.pending]（漏掉它們會讓新帳號
// 宣稱六維都練過，於是每一維真正的第一場都走成「非首場」）。
//
// 兩次都是靠人逐一想，兩次都有漏。這支改成反過來驗：
// **存檔裡的每一個欄位，歸零後都必須是空的**，除非它在下面的白名單上。
// 新增一個欄位卻忘了歸零 → 這支失敗；那個欄位對新帳號本來就該有值
// → 把它加進白名單，附上理由。無論哪一種，都逼出一個決定。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/commerce.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/domain/models.dart';
import 'package:fitness_app/domain/clock.dart';
import 'package:fitness_app/state/app_state.dart';

/// 「空」的定義：null、0、false、空字串、空集合，或每個值都是空的 Map。
bool isEmptyValue(Object? v) =>
    v == null ||
    v == 0 ||
    v == 0.0 ||
    v == false ||
    v == '' ||
    (v is List && v.isEmpty) ||
    (v is Map && (v.isEmpty || v.values.every(isEmptyValue)));

/// 新帳號**本來就該有值**的欄位，各自附理由。
///
/// 加東西進這張表是一個決定，不是一個修法 —— 每一行都要答得出
/// 「為什麼一個零次訓練的帳號會有這個」。
const allowed = <String, String>{
  'v': '存檔格式版本',
  'savedAt': '存檔時戳',

  // 註冊問卷填的 10 欄 ＋ 身分。歸零的是「使用紀錄」，不是「你是誰」。
  'displayName': '暱稱',
  'bodyweightKg': '體重',
  'heightCm': '身高',
  'isMale': '生理性別',
  'registeredOn': '註冊日',
  'signUpCompleted': '已完成註冊',
  // 合規紀錄，不是進度 —— 新帳號在註冊流程裡剛按過同意，本來就該有值。
  // `completeSignUp()` 刻意排在 `resetToNewAccount()` 之後寫入它。
  'agreedTermsVersion': '已同意的條款版本',
  'daysPerWeek': '問卷：每週訓練天數',
  'duration': '問卷：單次時長',
  'commonGoal': '問卷：目標',
  'experience': '問卷：經驗',
  'equipmentTier': '問卷：器材等級',
  'ownedEquipment': '問卷：持有器材',

  // `PreferredTimes` 是**固定七格**的骨架（索引 0–6 對應週一到週日），
  // 空的樣子就是七個空清單，不是 `[]`。`resetToNewAccount()` 確實把它
  // 設回 `PreferredTimes.empty()` 了 —— 這裡放行的是那個形狀，
  // 不是放行「沒清掉」。內容有沒有真的清掉，由 `persistence_test` 釘。
  'preferredTimes': '七格骨架，空的樣子就是七個空清單',

  // 能力值 Aggregate 的初始態。六維各 10 點是起點，不是殘留。
  'points': '六維初始值 10',
  'decayTimers': '各維退步計時器自註冊日起算',
  'lastTrainedDate': '＝註冊日',

  // 週期基準時戳。空值代表「還沒有基準」，會在第一次判定時憑空重置一輪。
  'aiResetMonth': 'AI 月度額度的重置基準',
  'lastSnapshotOn': '能力值日快照的基準',
  'mentorWeek': '師徒週計數器的基準',
  'dailyTaskDay': '每日任務的所屬日',
  'dailyTasks': '新帳號當天就有今日任務',

  // 狀態列舉的「正常」值不是空值。這三個另有期望值，見 [expected] ——
  // 只做空白豁免的話，殘留的「會員生效中」也會被放行。
  'trainNoticeStage': '訓練提醒階段＝正常',
  'checkInNoticeStage': '簽到提醒階段＝正常',
  'membership': '會員狀態＝無',

  // 註冊流程的最後一步是計畫推薦；問卷答案留著，就推薦得出一份。
  'currentPlanId': '依保留的問卷重新推薦的計畫',
  // 問卷剛填完 —— 值為註冊日，不是上一個帳號的時戳。
  'weightUpdatedAt': '＝註冊日',
  'surveyUpdatedAt': '＝註冊日',
  // 示範時鐘是工具，不是帳號資料。
  'demoClockOffsetMs': '示範時鐘偏移，不隨帳號歸零',

  // 偏好設定。
  'aiAutoOptimize': '偏好：AI 自動優化',
  'abilityPublic': '偏好：能力值公開',
  'overallGradePublic': '偏好：綜合等級公開',
  'metricUnits': '偏好：公制單位',
};

/// 有固定期望值的欄位。空白豁免擋不住「殘留成另一個非空值」。
const expected = <String, Object?>{
  'trainNoticeStage': 'normal',
  'checkInNoticeStage': 'normal',
  'membership': 'none',
};

/// 把每一個欄位都弄髒。
///
/// **必要**：假資料本來就是零的欄位（是否為教官、處罰、申訴…），
/// 若直接從假資料歸零，看不出它們有沒有被漏掉。
void dirtyEverything(AppState s) {
  s.pending[Dim.chest] = 400;
  // expGrantedOn / rewardCounterDay 是私有欄位，由發獎路徑寫入。
  // 今日發獎計數器全是私有欄位，由發獎路徑寫入 —— 這裡碰不到，
  // 它們的歸零由既有的每日任務測試覆蓋。
  s.autoOptimizeCount = 3;
  s.weightUpdatedAt = s.now;
  s.surveyUpdatedAt = s.now;
  s.skipWeightAsk();
  s.skipSurveyAsk();

  s.noviceStarted = true;
  s.noviceSelected = 'p_beginner';
  s.noviceChecked = true;
  s.noviceFinished = true;
  s.noviceRewardClaimed = true;
  s.socialUnlocked = true;

  s.returnTaskViewedAt = s.now;
  s.returnTaskDone = true;
  s.returnRewardClaimed = true;
  s.returnTaskDim = Dim.shoulders;
  s.returnTaskAssigned = true;

  s.membership = MembershipState.active;
  s.membershipExpiry = s.now.add(const Duration(days: 30));
  s.membershipLockedPlanIds = const ['p1'];
  s.purchasedPlanIds.add('p2');
  s.currentPlan = s.platformPlans.first;

  s.isInstructor = true;
  s.instructorStage = InstructorStage.approved;
  s.instructorReputation = 80;
  s.peakReputation = 120;
  s.instructorSpecialties.add('增肌');
  s.ratedThisWeek = true;
  s.taskRatingsThisWeek = 2;
  s.mentorRewardsThisWeek = 2;
  // 本週互動摘要的四個數字由提問與任務推導，不另存（見 `AppState.weeklyAssigned`）。
  s.questions.add(MentorQuestion(from: '學徒', text: '問', at: s.now));
  s.mentorTasks.add(MentorTask(title: '任務', detail: '', assignedAt: s.now));

  s.myViolations = 2;
  s.email = 'a@b.c';
  s.deletionRequestedAt = s.now;
  s.deletionCoolingDays = 30;
  s.demoClockOffset = const Duration(days: 3);

  s.aiMonthly = 14;
  s.aiPermanent = 6;
  s.myExercises.add(Exercise(
    id: 'c_x',
    name: '自建動作',
    dim: Dim.arms,
    type: ExerciseType.strength,
    relativeIntensity: 1,
    isCustom: true,
  ));
  // 互動計數只有公開路徑進得去（私有欄位）。
  s.toggleLike(s.visiblePosts.firstWhere((p) => p.author != s.displayName));
  s.rewardedRequests.add('Like:p1');
  s.receiveInbound(InboundRequest(
    id: 'i1',
    kind: InboundKind.teamInvite,
    from: '隊長',
    fromRank: 30,
    subject: '某隊',
    sentAt: s.now,
  ));
}

void main() {
  // [AppState.demoClockOffset] 寫的是**模組層級**的時鐘。
  // 不還原的話，這支弄髒的 3 天會漏到後面每一支測試上 ——
  // 實際上就漏過：streak_break_test 的門檻因此整組偏掉。
  tearDown(resetAppClock);

  test('存檔裡的每個欄位，歸零後都是空的', () {
    final s = AppState();
    dirtyEverything(s);

    // 先確認真的弄髒了 —— 否則這支測試是空的。
    final before = s.toSnapshot();
    final dirty = [
      for (final e in before.entries)
        if (!isEmptyValue(e.value) && !allowed.containsKey(e.key)) e.key
    ];
    expect(dirty.length, greaterThan(25),
        reason: '前提：要先有夠多非空欄位，這支才驗得到東西');

    s.resetToNewAccount();

    final after = s.toSnapshot();
    final leftovers = <String>[];
    for (final e in after.entries) {
      if (expected.containsKey(e.key)) {
        if (e.value != expected[e.key]) {
          leftovers.add('${e.key} = ${e.value}（應為 ${expected[e.key]}）');
        }
        continue;
      }
      if (allowed.containsKey(e.key)) continue;
      if (!isEmptyValue(e.value)) leftovers.add('${e.key} = ${e.value}');
    }
    expect(leftovers, isEmpty,
        reason: '\n這些欄位在歸零後還留著上一個帳號的資料：\n  '
            '${leftovers.join('\n  ')}\n'
            '要嘛在 resetToNewAccount 裡清掉，'
            '要嘛加進 allowed 並寫明為什麼新帳號該有它。');
  });

  test('白名單只列存檔裡真的有的欄位', () {
    final keys = AppState().toSnapshot().keys.toSet();
    final stale = allowed.keys.where((k) => !keys.contains(k)).toList();
    expect(stale, isEmpty,
        reason: '白名單裡有已經不存在的欄位：$stale —— 欄位刪了，豁免也該跟著刪');
  });

  test('白名單每一項都寫得出理由', () {
    for (final e in allowed.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key} 沒有理由');
    }
  });
}
