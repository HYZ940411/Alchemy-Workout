// 關注名單以 uid 為鍵（暱稱重構階段三，2026-09-28）。
//
// ## 這一階段收的是什麼
//
// 雲端的 `follows` 一直都是 uid 對 uid，而本機那份存的是暱稱。
// 兩者之間每次都要翻譯一次 —— 翻不出來就整筆丟掉，翻錯了就記到別人頭上。
//
// 三個實際後果，下面每一條各釘一個：
//
//   1. **對方改名 → 我的關注憑空消失**（名單上是舊名字，比對不到新的）
//   2. **兩個同名的人共用一筆關注**（關注其中一個，兩個都顯示已關注）
//   3. **對方還沒發布公開檔案 → 登入時整筆被丟掉**（名單少人、粉絲數也少）

import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

PublicProfile _p(String uid, String name, {int followers = 0}) =>
    PublicProfile(
        uid: uid, displayName: name, rank: 10, followers: followers);

void main() {
  group('關注名單以 uid 為鍵', () {
    test('對方改名，關注還在', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-a', '阿甲')]);
      s.toggleFollow('阿甲', uid: 'u-a');
      expect(s.isFollowing('阿甲', uid: 'u-a'), isTrue);

      // 他改名了。公開檔案是同一個 uid，只有 displayName 換了。
      s.applyPublicProfiles([_p('u-a', '阿甲改名了')]);

      expect(s.isFollowing('阿甲改名了', uid: 'u-a'), isTrue,
          reason: '改名不該讓關注消失 —— uid 沒變');
      expect(s.following.length, 1, reason: '不該變成兩個人');
      expect(s.followName(s.following.first), '阿甲改名了',
          reason: '名單上要顯示現在的名字，不是我當初看到的');
    });

    test('兩個同名的人，各自是各自的一筆', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-1', '小明'), _p('u-2', '小明')]);

      s.toggleFollow('小明', uid: 'u-1');

      expect(s.isFollowing('小明', uid: 'u-1'), isTrue);
      expect(s.isFollowing('小明', uid: 'u-2'), isFalse,
          reason: '關注的是其中一個，不是「所有叫小明的人」');
    });

    test('粉絲數不會因為撞名疊到別人頭上', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles(
          [_p('u-1', '小明', followers: 3), _p('u-2', '小明', followers: 8)]);

      s.toggleFollow('小明', uid: 'u-1');

      expect(s.followersOf('小明', uid: 'u-1'), 4);
      expect(s.followersOf('小明', uid: 'u-2'), 8, reason: '另一個小明不受影響');
    });
  });

  group('以雲端為準重新對齊', () {
    test('讀不到暱稱的 uid 也要留在名單上', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      // 對方還沒發布公開檔案 —— 名單上查不到他的名字。
      s.applyFollows({'u-陌生'}, {'u-粉絲'});

      expect(s.following, contains('u-陌生'),
          reason: '在此之前查不到暱稱就整筆丟掉，於是「他還沒發檔案」'
              '等於「我沒關注他」');
      expect(s.followerCount, 1);
      expect(s.followName('u-陌生'), isNotEmpty, reason: '至少要寫得出一個字');
    });

    test('另一台裝置取消的關注不會回來', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyFollows({'u-a', 'u-b'}, const {});
      expect(s.following.length, 2);

      // 我在另一台裝置上取消關注了 u-b，雲端只剩一筆。
      s.applyFollows({'u-a'}, const {});

      expect(s.following, {'u-a'},
          reason: '整份換掉，不是併入 —— 併入的話取消永遠回不來');
    });

    test('示範資料的假使用者不跟著被換掉', () {
      final s = AppState()..myUid = 'u-me'; // demo
      expect(s.following, isNotEmpty, reason: '前提：示範帳號有假關注');
      final fakes = s.following.length;

      s.applyFollows({'u-真的'}, const {});

      expect(s.following.length, fakes + 1,
          reason: '雲端本來就沒有那幾位，跟著換掉的話一登入就整批消失');
    });

    test('封鎖過的人不會從雲端回到粉絲名單', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      s.applyPublicProfiles([_p('u-壞人', '壞人')]);
      s.applyFollows(const {}, {'u-壞人'});
      expect(s.followerCount, 1);

      expect(s.blockUser('壞人', uid: 'u-壞人'), isTrue);
      expect(s.followerCount, 0);

      // 重新登入。**他那筆關係文件我刪不掉**（安全規則只讓建立者刪），
      // 所以雲端還是會把他報回來。
      s.applyFollows(const {}, {'u-壞人'});

      expect(s.followerCount, 0,
          reason: '「封鎖自動解除雙方關注」不該每次登入都被推翻一次');
    });
  });

  group('暱稱鍵的升級', () {
    test('對方發布公開檔案之後，名單上不會變成兩個人', () {
      final s = AppState(demo: false)..myUid = 'u-me';
      // 還查不到 uid 的時候關注他。
      s.toggleFollow('後來才註冊的人');
      expect(s.following.length, 1);

      s.applyPublicProfiles([_p('u-新', '後來才註冊的人')]);

      expect(s.following, {'u-新'}, reason: '同一個人只該有一筆，而且收斂到 uid');
      expect(s.isFollowing('後來才註冊的人', uid: 'u-新'), isTrue);
    });
  });

  group('舊存檔（存的是暱稱）', () {
    test('讀得回來，而且翻成鍵', () {
      final a = AppState(demo: false)..myUid = 'u-me';
      final snap = a.toSnapshot()
        ..remove('followingKeys')
        ..remove('followerKeys')
        // 階段三之前的欄位長這樣：一串暱稱。
        ..['following'] = ['老朋友']
        ..['followers'] = ['老粉絲'];

      final b = AppState(demo: false)..myUid = 'u-me';
      expect(b.applySnapshot(snap), isTrue);

      expect(b.isFollowing('老朋友'), isTrue);
      expect(b.isFollower('老粉絲'), isTrue);
      expect(b.followName(b.following.first), '老朋友',
          reason: '翻成鍵之後名字還要看得到');
    });

    test('翻得出 uid 的就此收斂到 uid', () {
      final b = AppState(demo: false)..myUid = 'u-me';
      b.applyPublicProfiles([_p('u-老', '老朋友')]);

      final snap = (AppState(demo: false)..myUid = 'u-me').toSnapshot()
        ..remove('followingKeys')
        ..['following'] = ['老朋友'];
      expect(b.applySnapshot(snap), isTrue);

      expect(b.following, {'u-老'});
    });

    test('關注名單存得回來（新格式）', () {
      final a = AppState(demo: false)..myUid = 'u-me';
      a.applyPublicProfiles([_p('u-a', '阿甲')]);
      a.toggleFollow('阿甲', uid: 'u-a');
      a.gainFollower('阿乙', uid: 'u-b');

      // **b 沒有讀過公開檔案** —— 名字只能靠存檔裡那一份墊底。
      final b = AppState(demo: false)..myUid = 'u-me';
      expect(b.applySnapshot(a.toSnapshot()), isTrue);

      expect(b.isFollowing('阿甲', uid: 'u-a'), isTrue);
      expect(b.isFollower('阿乙', uid: 'u-b'), isTrue);
      expect(b.followName('u-a'), '阿甲');
      expect(b.followName('u-b'), '阿乙');
    });
  });

  test('真帳號一開機沒有假關注', () {
    final s = AppState(demo: false);
    expect(s.following, isEmpty);
    expect(s.followers, isEmpty);
    expect(s.followTotal, 0,
        reason: '在此之前是 3 —— 師徒解鎖清單裡的「關注」對每個新帳號'
            '預設就是做過了');
  });
}
