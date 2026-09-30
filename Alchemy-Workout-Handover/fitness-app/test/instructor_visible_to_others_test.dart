// 當上教官之後，別人的拜師頁上要找得到他。
//
// ## 使用者 2026-09-29 實測：A 看不到 B 教官
//
// B 通過測驗、管理員核准（雲端 `instructor_cases` 的 `state` 是 `passed`）、
// B 自己也看到「我是教官了」—— 而**A 的教官清單裡沒有他**。
//
// 查雲端證實：B 的 `public_profiles` 文件 `isInstructor` 仍是 `false`。
//
// 根因是 `_becomeInstructor()` 只改本機三個欄位，**沒有重新發布公開檔案**。
// 而拜師頁跑的是 `instructors`，那份清單由別人的公開檔案建出來
// （`_applyInstructor` 讀 `p.isInstructor`）——
// 於是他當上了一個**沒有人找得到的教官**。
//
// 這與「評分細則沒送到審核者面前」「顏色算了卻沒畫出來」同一家族：
// 狀態改對了，而改對的那件事沒有傳到需要它的地方。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/instructor_case_data.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/ability.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/state/app_state.dart';

/// 記下每一次公開檔案發布。
class _Profiles implements PublicProfileSource {
  final List<PublicProfile> published = [];
  @override
  Future<void> publish(PublicProfile me) async => published.add(me);
  @override
  Future<List<PublicProfile>> others({int limit = kProfileFetchLimit}) async =>
      const [];
  @override
  Future<List<PublicProfile>> byUids(List<String> uids) async => const [];
  @override
  Future<LeaderboardPage?> leaderboard({
    required bool weekly,
    required int group,
    required int myScore,
    int window = 10,
  }) async =>
      null;
  @override
  Future<void> remove() async {}
}

/// 只回一個固定裁決的來源。
class _Verdict implements InstructorCaseSource {
  final InstructorVerdict v;
  _Verdict(this.v);
  @override
  Future<InstructorVerdict?> mine() async => v;
  @override
  Future<void> file(CloudInstructorCase c) async {}
  @override
  Future<List<CloudInstructorCase>> queue({int limit = 100}) async => const [];
  @override
  Future<void> decide(String uid,
      {required bool passed, required String handlerName}) async {}
}

void main() {
  test('核准後，公開檔案帶著教官身分重新發布', () async {
    final profiles = _Profiles();
    final s = AppState(demo: false)
      ..myUid = 'u-b'
      ..profileSource = profiles
      ..instructorCaseSource = _Verdict(InstructorVerdict.passed);

    await s.loadMyInstructorVerdict();

    expect(s.isInstructor, isTrue, reason: '前提：本機已成為教官');
    expect(profiles.published, isNotEmpty,
        reason: '不發布的話，他當上了一個沒有人找得到的教官');
    final me = profiles.published.last;
    expect(me.isInstructor, isTrue);
    expect(me.apprenticeCap, greaterThan(0),
        reason: '少了名額，「名額已滿」擋不住');
    expect(me.reputation, isNotNull);
  });

  test('別人讀到那份公開檔案，就會出現在他的教官清單裡', () {
    final a = AppState(demo: false);
    expect(a.instructors, isEmpty, reason: '前提：真帳號的清單本來是空的');

    a.applyPublicProfiles([
      PublicProfile(
        uid: 'u-b',
        displayName: 'B 教官',
        rank: 13,
        grade: 'B',
        ability: {for (final d in Dim.values) d: 30},
        followers: 0,
        isInstructor: true,
        reputation: 100,
        apprentices: 0,
        apprenticeCap: 5,
        specialties: const ['增肌'],
      ),
    ]);

    expect(a.instructors.map((i) => i.name), contains('B 教官'));
    expect(a.instructors.first.apprenticeCap, 5);
  });

  test('教官身分被撤銷時，公開檔案照樣要更新到別人那邊', () {
    final a = AppState(demo: false);
    a.applyPublicProfiles([
      PublicProfile(
        uid: 'u-b',
        displayName: 'B 教官',
        rank: 13,
        grade: 'B',
        ability: {for (final d in Dim.values) d: 30},
        followers: 0,
        isInstructor: true,
        reputation: 100,
        apprentices: 0,
        apprenticeCap: 5,
      ),
    ]);
    expect(a.instructors, isNotEmpty);

    // 撤銷之後那份檔案的 isInstructor 變 false。
    a.applyPublicProfiles([
      PublicProfile(
        uid: 'u-b',
        displayName: 'B 教官',
        rank: 13,
        grade: 'B',
        ability: {for (final d in Dim.values) d: 30},
        followers: 0,
      ),
    ]);
    expect(a.instructors.map((i) => i.name), isNot(contains('B 教官')),
        reason: '留著的話他一直出現在拜師頁上，而申請會被對方那側擋下');
  });

  test('早就是教官、但公開檔案是舊的 —— 下次登入要自己補上', () async {
    // `_becomeInstructor()` 開頭是 `if (isInstructor) return;`，
    // 所以已經是教官的人不會再跑到裡面那句發布。
    // 在「發布」這件事修好之前就當上教官的人（例如使用者 2026-09-29
    // 測到那位），公開檔案會永遠停在 isInstructor: false。
    final profiles = _Profiles();
    final s = AppState(demo: false)
      ..myUid = 'u-old'
      ..isInstructor = true // 已經是教官了
      ..profileSource = profiles
      ..instructorCaseSource = _Verdict(InstructorVerdict.passed);

    await s.loadMyInstructorVerdict();

    expect(profiles.published, isNotEmpty,
        reason: '不補的話，別人的拜師頁上永遠沒有他');
    expect(profiles.published.last.isInstructor, isTrue);
  });

  test('駁回的人不會被發布成教官', () async {
    final profiles = _Profiles();
    final s = AppState(demo: false)
      ..myUid = 'u-c'
      ..profileSource = profiles
      ..instructorCaseSource = _Verdict(InstructorVerdict.rejected);

    await s.loadMyInstructorVerdict();
    expect(s.isInstructor, isFalse);
    expect(s.instructorStage, InstructorStage.rejected);
    for (final p in profiles.published) {
      expect(p.isInstructor, isFalse);
    }
  });
}
