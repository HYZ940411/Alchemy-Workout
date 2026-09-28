// 接受邀請失敗時要說得出原因（2026-09-28）。
//
// 雙人實測 T2：A 邀 B 進團隊 → B 接受 → **重整也沒有**。
//
// 兩個問題疊在一起：
//
// ① `publicTeams.firstWhere((x) => x.name == r.subject)` **沒有 orElse**
//    —— 找不到就丟例外。而「找不到」是真的會發生：那份清單要載入過
//    才有東西，使用者若從通知直接點進信箱就是空的。
// ② 畫面固定印「沒有成功」。對使用者沒有用，對查問題的人也沒有用 ——
//    T2 卡了整個下午，而沒有任何地方說得出是哪一段斷的。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/community.dart';
import 'package:fitness_app/domain/inbound.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/state/app_state.dart';

InboundRequest invite(String team) => InboundRequest(
      id: 'req-$team',
      kind: InboundKind.teamInvite,
      from: '隊長',
      fromRank: 30,
      subject: team,
      sentAt: DateTime.now(),
    );

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  test('清單裡沒有那支隊時，不丟例外而且說得出原因', () {
    final s = AppState()..myTeam = null;
    final r = invite('查無此隊');
    s.inbox.insert(0, r);

    expect(s.acceptInbound(r), isFalse);
    // 訊息本身早就存在（`inboundBlockedReason` 回「這支團隊已經不在了」），
    // **只是從來沒有傳到畫面上** —— `acceptInbound` 直接回 false，
    // 而畫面印死的「沒有成功」。
    expect(s.inboundFailure, isNotNull, reason: '原因要傳得到畫面');
    expect(s.inboundFailure, contains('團隊'));
  });

  test('團隊沒有雲端識別碼時擋下來 —— 不讓他加入一個存不住的隊', () {
    final s = AppState()..myTeam = null;
    // 沒有 id 的公開團隊：`_joinPublicTeam` 會自己編一個本機 id，
    // 而 `putMember` 寫去的是一份雲端不存在的文件 —— 重整就沒了。
    s.publicTeams.insert(
      0,
      const PublicTeam('沒有識別碼的隊', 1, 5),
    );
    final r = invite('沒有識別碼的隊');
    s.inbox.insert(0, r);

    expect(s.acceptInbound(r), isFalse);
    expect(s.inboundFailure, contains('雲端識別碼'));
    expect(s.myTeam, isNull, reason: '不該在本機假裝加入了');
  });

  test('成功時不留下失敗訊息', () {
    final s = AppState()..myTeam = null;
    final t = s.publicTeams.firstWhere((x) => x.id.isNotEmpty,
        orElse: () => s.publicTeams.first);
    if (t.id.isEmpty) return; // 假資料沒有 id 的話跳過
    final r = invite(t.name);
    s.inbox.insert(0, r);

    expect(s.acceptInbound(r), isTrue);
    expect(s.inboundFailure, isNull);
    expect(s.myTeam?.name, t.name);
  });
}
