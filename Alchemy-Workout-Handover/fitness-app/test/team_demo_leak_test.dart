// 真實帳號不該被塞進一支他沒加入的隊伍。
//
// 使用者回報「團隊裡還有不明的成員」。查下去是示範資料的旗標漏了一個：
// `myTeam` 是 `AppState` 裡**唯一**沒有跟著 `demo` 走的使用者狀態集合，
// 其餘十七個都是 `late X = demo ? buildX() : []`。
//
// 而且它藏得很深 —— `resetToNewAccount()` 有清它，但那**只在讀不到
// 存檔時跑**。第二次之後的登入走 `applySnapshot()`，而 `myTeam` 不在
// 快照裡，於是每次重開都從建構子重新長出一支「晨型人訓練隊」，
// 隊友是早鳥訓練、Yuki、核心怪物 —— 三個不存在的人。
//
// 第二道破口在 `applyCloudTeam(null)`：雲端回報「這個人沒有隊伍」時
// 它直接 `return`，把假隊伍留在原地。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/team_data.dart';
import 'package:fitness_app/state/app_state.dart';

void main() {
  group('示範隊伍不得出現在真實帳號上', () {
    test('demo:false 建出來就沒有隊伍', () {
      final s = AppState(demo: false);
      expect(s.myTeam, isNull);
      expect(s.teamJoinedAt, isNull, reason: '沒加入過就沒有加入時戳');
      expect(s.publicTeams, isEmpty);
    });

    test('demo:true 仍有示範隊伍 —— 既有測試的前提', () {
      final s = AppState();
      expect(s.myTeam, isNotNull);
      expect(s.myTeam!.members.length, 4);
    });

    test('雲端說沒有隊伍，本機那支就要消失', () {
      // 這是第二次之後登入會走的路：有存檔 → 不呼叫 resetToNewAccount，
      // myTeam 還是建構子給的那支。
      final s = AppState();
      expect(s.myTeam, isNotNull, reason: '前提：本機有一支示範隊伍');

      s.applyCloudTeam(null);

      expect(s.myTeam, isNull);
      expect(s.teamJoinedAt, isNull);
    });

    test('隊伍已解散也一樣要消失', () {
      final s = AppState();
      s.applyCloudTeam(const CloudTeam(
        id: 't-x',
        name: '已解散的隊',
        members: {},
        isPublic: true,
        capacity: 5,
        peakSize: 3,
        disbanded: true,
      ));
      expect(s.myTeam, isNull);
    });

    test('雲端真的有隊伍時照常帶進來', () {
      final s = AppState(demo: false);
      s.applyCloudTeam(const CloudTeam(
        id: 't-real',
        name: '真的隊伍',
        members: {},
        isPublic: true,
        capacity: 5,
        peakSize: 2,
      ));
      expect(s.myTeam?.name, '真的隊伍');
    });

    test('新帳號歸零時也沒有隊伍', () {
      final s = AppState()..resetToNewAccount();
      expect(s.myTeam, isNull);
      expect(s.teamJoinedAt, isNull);
      expect(s.teamLeftAt, isNull);
    });
  });
}
