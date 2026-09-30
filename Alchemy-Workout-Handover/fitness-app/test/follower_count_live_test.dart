// 粉絲數要數關係本身，不是讀對方檔案上的數字（2026-09-24）。
//
// 使用者回報：「我封鎖過對方，雖然粉絲不是 0，但是我重新追蹤刷新後，
// 顯示還是 0。」
//
// 根因：畫面顯示的是 `public_profiles/{uid}.followers` 這個衍生計數，
// 而那份文件**只有本人寫得了**（安全規則：只有本人可寫）。所以我關注
// 某人，`follows/` 多了一筆、對方的 `followers` 欄位不動 —— 一重新整理，
// `applyPublicProfiles` 把本機計數重設成對方檔案上的舊值，我的 +1 就消失。
//
// **那是必然，不是偶發。** 改成直接數 `follows` 集合（它才是關係的真相
// 來源），不依賴對方登入。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/follow_data.dart';
import 'package:fitness_app/data/public_profile.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeFollows implements FollowSource {
  /// uid → 現在有幾個粉絲（模擬 `follows` 集合數出來的結果）。
  final Map<String, int> counts;
  final List<String> counted = [];
  bool offline = false;

  _FakeFollows(this.counts);

  @override
  Future<int> followerCountOf(String uid) async {
    counted.add(uid);
    if (offline) throw StateError('離線');
    return counts[uid] ?? 0;
  }

  @override
  Future<void> follow(String targetUid) async {}
  @override
  Future<void> unfollow(String targetUid) async {}
  @override
  Future<Set<String>> following() async => const {};
  @override
  Future<Set<String>> followers() async => const {};
}

/// 對方的公開檔案寫著 [stale] —— 那是他上次登入時的數字。
AppState _wired(_FakeFollows src, {int stale = 0}) {
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..followSource = src;
  s.applyPublicProfiles([
    PublicProfile(
        uid: 'u-阿甲', displayName: '阿甲', rank: 30, followers: stale),
  ]);
  return s;
}

void main() {
  group('粉絲數以 follows 集合為準', () {
    test('數出來的值取代檔案上那個舊數字', () async {
      final src = _FakeFollows({'u-阿甲': 7});
      final s = _wired(src, stale: 0);
      expect(s.followersOf('阿甲', uid: 'u-阿甲'), 0, reason: '前提：檔案上寫 0');

      await s.ensureFollowerCount('阿甲', 'u-阿甲');

      expect(s.followersOf('阿甲', uid: 'u-阿甲'), 7);
    });

    test('數完之後我再關注他，+1 疊得上去', () async {
      final src = _FakeFollows({'u-阿甲': 7});
      final s = _wired(src);
      await s.ensureFollowerCount('阿甲', 'u-阿甲');

      s.toggleFollow('阿甲');

      // 那一刻的樂觀更新比剛數回來的值更新 —— 那筆關注已經寫進
      // `follows`，只是這裡還沒重數。
      expect(s.followersOf('阿甲', uid: 'u-阿甲'), 8);
    });

    test('同一個人不重複數', () async {
      final src = _FakeFollows({'u-阿甲': 7});
      final s = _wired(src);
      await Future.wait([
        s.ensureFollowerCount('阿甲', 'u-阿甲'),
        s.ensureFollowerCount('阿甲', 'u-阿甲'),
      ]);
      expect(src.counted, hasLength(1));
    });

    test('自己不必數 —— 自己的粉絲清單就在手上', () async {
      final src = _FakeFollows({});
      final s = _wired(src);
      await s.ensureFollowerCount('我', 'u-me');
      expect(src.counted, isEmpty);
    });

    test('數不到就維持現狀，不把畫面洗掉', () async {
      final src = _FakeFollows({'u-阿甲': 7})..offline = true;
      final s = _wired(src, stale: 3);

      await s.ensureFollowerCount('阿甲', 'u-阿甲');

      expect(s.followersOf('阿甲', uid: 'u-阿甲'), 3);
      // 失敗之後不該把這個人鎖住，下次要能再試。
      src.offline = false;
      await s.ensureFollowerCount('阿甲', 'u-阿甲');
      expect(s.followersOf('阿甲', uid: 'u-阿甲'), 7);
    });

    test('沒接後端就什麼都不做', () async {
      final s = AppState(demo: false)..myUid = 'u-me';
      await s.ensureFollowerCount('阿甲', 'u-阿甲'); // 不該拋出來
    });
  });
}
