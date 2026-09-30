// 教官側的本機模型補上學徒身分（`[BE-15]`，2026-09-24）。
//
// 在此之前 `mentorTasks`／`questions` 是**一份共用清單**，沒有記錄
// 「這則是哪位學徒的」，而雲端的任務與問答掛在特定師徒關係下。後果：
//
//   · `applyCloudBonds` 只處理 `apprenticeUid == me` —— 教官收了徒，
//     重新登入學徒清單是空的
//   · `MentorSource.tasks()` 與 `questions()` **一個呼叫端都沒有** ——
//     學徒的提問寫進了 Firestore，教官永遠讀不到
//   · `answerQuestion()` 整個函式只有一個計數器，回答的文字由畫面
//     直接寫進物件，沒有任何雲端寫入 —— 學徒永遠看不到回答
//   · 學徒給的評分同樣讀不回來，所以拜師頁上每位教官都是「0.0（0 則）」，
//     而那不是「還沒被評過」，是這個數字從來不存在
//
// `data_source_wiring_test` 沒抓到 `tasks()`／`questions()`：畫面上有個
// 同名的 `s.questions` 欄位，方法名撞到欄位名。那是第二種撞名成因。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/mentor_data.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeMentor implements MentorSource {

  /// 恢復提議。只記下來，需要的測試自己讀。
  final List<(String bond, String? by)> restoreCalls = [];

  @override
  Future<void> proposeRestore(String bondId, String byUid) async =>
      restoreCalls.add((bondId, byUid));

  @override
  Future<void> dropRestore(String bondId) async =>
      restoreCalls.add((bondId, null));


  /// 週互動評分。這支測試不碰它 —— 記下來就好。
  final List<(String bond, String week, int stars)> weekRatings = [];

  @override
  Future<void> rateWeek(String bondId, String week, int stars) async =>
      weekRatings.add((bondId, week, stars));

  final Map<String, List<CloudMentorTask>> cloudTasks = {};
  final Map<String, List<CloudQuestion>> cloudQuestions = {};
  final List<(String bond, String taskId)> putTasks = [];
  final List<(String bond, String qId, String text)> answers = [];

  @override
  Future<List<CloudMentorTask>> tasks(String bondId) async =>
      cloudTasks[bondId] ?? const [];

  @override
  Future<List<CloudQuestion>> questions(String bondId) async =>
      cloudQuestions[bondId] ?? const [];

  @override
  Future<void> putTask(String bondId, CloudMentorTask t) async =>
      putTasks.add((bondId, t.id));

  @override
  Future<void> answer(
          String bondId, String questionId, String text, DateTime at) async =>
      answers.add((bondId, questionId, text));

  @override
  Future<List<CloudBond>> bonds() async => const [];
  @override
  Future<void> bond(CloudBond b) async {}
  @override
  Future<void> release(
      String bondId, MentorReleaseReason reason, DateTime at) async {}
  @override
  Future<void> recover(String bondId, DateTime now) async {}
  @override
  Future<void> ask(String bondId, CloudQuestion q) async {}
  @override
  Future<List<MentorRequest>> requestsFor(String uid) async => const [];

  /// 我自己送出去的申請。預設沒有 —— 需要的測試自己覆寫。
  @override
  Future<List<MentorRequest>> sentRequests() async => sent;
  List<MentorRequest> sent = const [];
  @override
  Future<void> sendRequest(MentorRequest r) async {}
  @override
  Future<void> dropRequest(String requestId) async {}
  @override
  Stream<void> watchMentor() => const Stream.empty();
}

CloudBond _bond(String mentor, String apprentice,
        {MentorBondState state = MentorBondState.active}) =>
    CloudBond(
      id: '${mentor}_$apprentice',
      mentorUid: mentor,
      apprenticeUid: apprentice,
      mentorName: '老王',
      apprenticeName: '小明',
      state: state,
      bondedAt: DateTime(2026, 9, 1),
    );

({AppState s, _FakeMentor src}) _mentor() {
  final src = _FakeMentor();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..isInstructor = true
    // 指派任務的 Precondition：已確認指導責任聲明的現行版本。
    ..instructorDutyVersion = kInstructorDutyVersion
    ..mentorSource = src;
  return (s: s, src: src);
}

void main() {
  group('教官側的師徒關係要載得回來', () {
    test('我帶的學徒會出現在清單上', () {
      final m = _mentor();
      expect(m.s.apprentices, isEmpty, reason: '前提：原本是空的');

      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);

      // 在此之前 `applyCloudBonds` 只看 `apprenticeUid == me` ——
      // 教官收了徒，重新登入學徒清單是空的。
      expect(m.s.apprentices.map((a) => a.uid), ['u-小明']);
    });

    test('已解除的關係不留在學徒名單上', () {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      expect(m.s.apprentices, hasLength(1));

      m.s.applyCloudBonds(
          [_bond('u-me', 'u-小明', state: MentorBondState.released)]);

      expect(m.s.apprentices, isEmpty);
    });

    test('同一位學徒不會重複加入', () {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      expect(m.s.apprentices, hasLength(1));
    });

    test('別人的關係不會混進來', () {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-別人', 'u-小華')]);
      expect(m.s.apprentices, isEmpty);
    });

    test('關係 ID 兩側算出來的是同一個', () {
      final m = _mentor();
      expect(m.s.mentorBondIdFor('u-小明'), 'u-me_u-小明');
      // 學徒那一側的 `_apprenticeBondId` 是 `教官uid_我的uid`，
      // 所以教官算「我_學徒」、學徒算「教官_我」—— 必須一致。
      expect(_bond('u-me', 'u-小明').id, m.s.mentorBondIdFor('u-小明'));
    });
  });

  group('學徒側：我的教官', () {
    /// 學徒那一側 —— 我是 `apprenticeUid`。
    ({AppState s, _FakeMentor src}) apprentice() {
      final src = _FakeMentor();
      final s = AppState(demo: false)
        ..myUid = 'u-me'
        ..mentorSource = src;
      return (s: s, src: src);
    }

    test('公開檔案還沒載回來，關係也要成立', () {
      final a = apprentice();
      expect(a.s.nameByUid['u-師父'], isNull, reason: '前提：查不到這個人的名字');

      a.s.applyCloudBonds([_bond('u-師父', 'u-me')]);

      // 在此之前這裡是 `nameByUid[...]`，查不到就 `continue` —— 整段
      // 關係被靜靜跳過。而上面教官那一段寫的是 `?? b.apprenticeName`，
      // 同一個決定寫在兩個地方，只有一處做對。
      //
      // 公開檔案是另一塊各自成敗的同步；它慢了或失敗了，使用者看到的
      // 就是「我的教官不見了」，而雲端好端端的。
      expect(a.s.myInstructor?.name, '老王');
      expect(a.s.myInstructor?.uid, 'u-師父');
    });

    test('公開檔案載回來了就用那個名字 —— 對方改過暱稱', () {
      final a = apprentice();
      a.s.nameByUid['u-師父'] = '王教官';

      a.s.applyCloudBonds([_bond('u-師父', 'u-me')]);

      expect(a.s.myInstructor?.name, '王教官');
    });

    test('我當教官的那一段不會被誤認成我的教官', () {
      final a = apprentice();
      a.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      expect(a.s.myInstructor, isNull);
    });
  });

  group('教官讀得回任務與問答', () {
    test('讀回來的問答帶著是哪位學徒問的', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      m.src.cloudQuestions['u-me_u-小明'] = [
        CloudQuestion(
          id: 'q1',
          fromUid: 'u-小明',
          text: '深蹲膝蓋會痛怎麼辦',
          at: DateTime(2026, 9, 20),
        ),
      ];

      await m.s.loadMentorSide();

      expect(m.s.questions, hasLength(1));
      // 沒有這個欄位，教官會在小明的頁面上看到小華問的問題。
      expect(m.s.questions.single.apprenticeUid, 'u-小明');
      expect(m.s.questions.single.text, '深蹲膝蓋會痛怎麼辦');
    });

    test('讀回來的任務帶著評分', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      m.src.cloudTasks['u-me_u-小明'] = [
        const CloudMentorTask(
            id: 't1', title: '練腿', detail: '', rating: 5),
      ];

      await m.s.loadMentorSide();

      expect(m.s.mentorTasks.single.rating, 5);
      expect(m.s.mentorTasks.single.apprenticeUid, 'u-小明');
    });

    test('重複讀不會長出兩份', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      m.src.cloudTasks['u-me_u-小明'] = [
        const CloudMentorTask(id: 't1', title: '練腿', detail: ''),
      ];

      await m.s.loadMentorSide();
      await m.s.loadMentorSide();

      expect(m.s.mentorTasks, hasLength(1));
    });

    test('讀不到就維持現狀，不把任務清空', () async {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);
      m.s.mentorTasks.add(MentorTask(
          id: 'local', title: '本機的', detail: '', apprenticeUid: 'u-小明'));

      await m.s.loadMentorSide(); // 雲端沒資料

      expect(m.s.mentorTasks, hasLength(1));
    });
  });

  group('教官回答問題', () {
    test('回答會寫上雲端，掛在正確的關係下', () {
      final m = _mentor();
      final q = MentorQuestion(
        id: 'q1',
        from: '小明',
        apprenticeUid: 'u-小明',
        text: '問題',
        at: DateTime(2026, 9, 20),
      );
      m.s.questions.add(q);

      expect(m.s.answerQuestion(q, '這樣做'), isTrue);

      // 在此之前 `answerQuestion()` 只有一個計數器 ——
      // 學徒永遠看不到回答。
      expect(m.src.answers, [('u-me_u-小明', 'q1', '這樣做')]);
      expect(q.answer, '這樣做');
      expect(q.answeredAt, isNotNull);
    });

    test('空白的回答不算', () {
      final m = _mentor();
      final q = MentorQuestion(
          id: 'q1', from: '小明', apprenticeUid: 'u-小明',
          text: '問題', at: DateTime(2026, 9, 20));
      expect(m.s.answerQuestion(q, '   '), isFalse);
      expect(q.answer, isNull);
      expect(m.src.answers, isEmpty);
    });
  });

  group('指派任務', () {
    test('帶著是指派給哪位學徒，並寫到那段關係下', () {
      final m = _mentor();
      m.s.applyCloudBonds([_bond('u-me', 'u-小明')]);

      m.s.assignMentorTask('練腿', '三組', apprenticeUid: 'u-小明');

      final t = m.s.mentorTasks.first;
      expect(t.apprenticeUid, 'u-小明');
      expect(m.src.putTasks, [('u-me_u-小明', t.id)]);
    });

    test('任務有自己的 ID，同名任務不會互相覆蓋', () {
      final m = _mentor();
      m.s.assignMentorTask('練腿', 'A', apprenticeUid: 'u-小明');
      m.s.assignMentorTask('練腿', 'B', apprenticeUid: 'u-小明');

      // 在此之前雲端拿標題當 ID —— 兩則會落在同一份文件上。
      final ids = m.s.mentorTasks.map((t) => t.id).toSet();
      expect(ids, hasLength(2));
    });
  });

  group('星等由任務上的評分推導', () {
    test('沒有評分時是 0 則 —— 畫面要據此顯示「尚無評分」', () {
      final m = _mentor();
      expect(m.s.myRatingStats.count, 0);
    });

    test('平均與次數都算得出來', () {
      final m = _mentor();
      m.s.mentorTasks.addAll([
        MentorTask(
            id: 'a', title: 'a', detail: '', apprenticeUid: 'u-小明', rating: 5),
        MentorTask(
            id: 'b', title: 'b', detail: '', apprenticeUid: 'u-小明', rating: 3),
        MentorTask(id: 'c', title: 'c', detail: '', apprenticeUid: 'u-小明'),
      ]);

      expect(m.s.myRatingStats.count, 2, reason: '未評分的不算');
      expect(m.s.myRatingStats.avg, 4);
    });

    test('我當學徒時收到的任務不算進我的星等', () {
      final m = _mentor();
      // `apprenticeUid` 為空＝這是指派給我的，我是學徒那一側。
      m.s.mentorTasks
          .add(MentorTask(id: 'x', title: 'x', detail: '', rating: 1));
      expect(m.s.myRatingStats.count, 0);
    });

    test('星等跟著公開檔案發布出去', () {
      final m = _mentor();
      m.s.mentorTasks.add(MentorTask(
          id: 'a', title: 'a', detail: '', apprenticeUid: 'u-小明', rating: 4));

      final me = m.s.myPublicProfile('u-me');
      expect(me.ratingCount, 1);
      expect(me.avgRating, 4);
    });
  });
}
