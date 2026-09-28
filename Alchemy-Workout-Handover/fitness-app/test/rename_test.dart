// 開放改名（暱稱重構階段五，使用者裁決 A，2026-09-28）。
//
// ## 規格給的與沒給的
//
// 〈註冊流程〉定死了三件事：**位置**（設定頁）、**長度**（1–12 字）、
// **不要求全平台唯一**（「暱稱為顯示名稱，不是識別碼」）。
//
// 規格**沒有**規定改名頻率。使用者裁決 A：每 30 天一次，理由是
// `02_Aggregate定義.md` 把顯示名稱列為「供待審佇列與稽核呈現」——
// 管理員是靠名字認人的，不限次數的話被檢舉的人改個名字就換了一張臉。
//
// ## 為什麼這一階段要排在最後
//
// 階段一～四把「這是誰」從暱稱收斂到 uid。在那之前開放改名，
// 使用者的舊貼文會編輯不了、違規點數會記到同名的人頭上、
// 關注名單會憑空少人。這個檔案的最後一組就是在驗那件事。

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/registration.dart';
import 'package:fitness_app/domain/rewards.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

AppState _me() => AppState(demo: false)
  ..myUid = 'u-me'
  ..displayName = '小明';

void main() {
  group('改名本身', () {
    test('改得動，而且立刻生效', () {
      final s = _me();
      expect(s.rename('阿華'), isNull);
      expect(s.displayName, '阿華');
    });

    test('太長不行，空白不行', () {
      final s = _me();
      expect(s.rename('一' * (kNicknameMaxLength + 1)), isNotNull);
      expect(s.rename('   '), isNotNull);
      expect(s.displayName, '小明', reason: '擋下來就不該改到');
    });

    test('改成一樣的不算改 —— 不然可以拿它繞過冷卻期', () {
      final s = _me();
      expect(s.rename('小明'), isNotNull);
      expect(s.lastRenamedAt, isNull);
    });

    test('前後空白會去掉', () {
      final s = _me();
      s.rename('  阿華  ');
      expect(s.displayName, '阿華');
    });

    test('不檢查全平台唯一 —— 暱稱不是識別碼', () {
      final s = _me();
      s.applyPublicProfiles(
          [PublicProfile(uid: 'u-other', displayName: '阿華', rank: 1)]);
      expect(s.rename('阿華'), isNull);
    });
  });

  group('30 天冷卻期（裁決 A）', () {
    test('剛改完就不能再改，而且說得出還要等幾天', () {
      final s = _me();
      s.rename('阿華');
      final why = s.renameBlockedReason();
      expect(why, isNotNull);
      expect(why, contains('30'));
      expect(s.rename('第三個名字'), isNotNull);
      expect(s.displayName, '阿華');
    });

    test('滿 30 天就能再改', () {
      final s = _me();
      s.rename('阿華');
      s.advanceDemoClock(const Duration(days: 30));
      expect(s.renameBlockedReason(), isNull);
      expect(s.rename('第三個名字'), isNull);
    });

    test('差一天還是不行', () {
      final s = _me();
      s.rename('阿華');
      s.advanceDemoClock(const Duration(days: 29));
      expect(s.renameBlockedReason(), isNotNull);
    });

    test('從來沒改過的人不受限', () {
      expect(_me().renameBlockedReason(), isNull);
    });
  });

  group('曾用名', () {
    test('留著，新的在前', () {
      final s = _me();
      s.rename('阿華');
      s.advanceDemoClock(const Duration(days: 31));
      s.rename('大雄');
      expect(s.formerNames, ['阿華', '小明']);
    });

    test('存得回來', () {
      final a = _me();
      a.rename('阿華');
      final b = AppState(demo: false)..myUid = 'u-me';
      expect(b.applySnapshot(a.toSnapshot()), isTrue);
      expect(b.formerNames, ['小明']);
      expect(b.renameBlockedReason(), isNotNull,
          reason: '冷卻期存不回來的話，重開 App 就能再改一次');
    });

    test('新帳號沒有曾用名，也沒有冷卻', () {
      final s = _me();
      s.rename('阿華');
      s.resetToNewAccount();
      expect(s.formerNames, isEmpty);
      expect(s.renameBlockedReason(), isNull);
    });
  });

  group('改名之後，前四個階段的成果', () {
    test('自己的舊貼文還是自己的，而且顯示新名字', () {
      final s = _me();
      s.posts.add(Post(
        id: 'p1',
        author: '小明',
        authorUid: 'u-me',
        authorRank: 1,
        text: '今天練腿',
        at: DateTime(2026, 9, 20),
      ));
      s.rename('阿華');

      final p = s.posts.first;
      expect(s.isMyPost(p), isTrue, reason: '階段一：身分以 uid 判定');
      expect(s.nameOf(p.author, uid: p.authorUid), '阿華',
          reason: '階段四：顯示名稱去查現值');
    });

    test('關注名單不會少人', () {
      final s = _me();
      s.applyPublicProfiles(
          [PublicProfile(uid: 'u-a', displayName: '阿甲', rank: 1)]);
      s.toggleFollow('阿甲', uid: 'u-a');
      s.rename('阿華');
      expect(s.isFollowing('阿甲', uid: 'u-a'), isTrue,
          reason: '階段三：關注名單以 uid 為鍵');
    });

    test('團隊貢獻不會歸零重算', () {
      final s = AppState()..myUid = 'u-me';
      // 名冊上的我要帶 uid，貢獻才會記在 uid 那一格。
      final t = s.myTeam!;
      final i = t.members.indexWhere((m) => m.name == s.displayName);
      t.members[i] = TeamMember(
          t.members[i].name, t.members[i].rank, t.members[i].role, uid: 'u-me');
      // 重新分隊期內不累加，那不是這條要驗的東西。
      var guard = 0;
      while (inRegroupWindow(s.now) && guard++ < 40) {
        s.advanceDemoClock(const Duration(days: 1));
      }
      s.startWorkout(s.platformPlans.firstWhere((p) => p.id == 'p_push'));
      s.completeCurrentSet();
      s.backdateSession(const Duration(minutes: 10));
      s.finishWorkout(EndKind.completed);

      final before = t.contributions['u-me'];
      expect(before, isNotNull, reason: '前提：貢獻真的記在 uid 那一格');

      s.rename('阿華');

      expect(t.contributions['u-me'], before,
          reason: '貢獻以 uid 為鍵，改名之後查得到同一筆');
      expect(t.contributions.containsKey(s.personKeyOf('阿華', null)), isFalse,
          reason: '不該因為改名而長出第二筆');
    });
  });
}
