// 累計違規次數要離開這台裝置（`[BE-13]`，2026-09-25）。
//
// 在此之前 `_setViolations()` 對別人寫的是 `AppState._violations` 這個
// **本機 Map** —— 管理員判了別人違規三次，對方那邊完全不知道，
// 而且管理員自己重開 App 也歸零。階梯累犯制等於只對自己成立。
//
// ## 為什麼另開一個 collection
//
// 這個數字決定處罰級距，所以**必須是當事人自己改不動的**。
// 既有的兩個候選位置都不行：`public_profiles/{uid}` 與 `users/{uid}/…`
// 的規則都是「本人可寫」—— 他自己就能清掉。
// 所以 `violations/{uid}`：管理員可寫、當事人唯讀。
//
// ## 為什麼記點看 uid 不看暱稱
//
// 暱稱會改，也會撞名。寫到暱稱底下的話，改名就斷了、撞名就記到
// 別人頭上。2026-09-25 之前送出的案件沒有 uid，那些**審得了但記不了點**
// —— 那是刻意的：記錯人比不記更糟。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/data/violation_data.dart';
import 'package:fitness_app/domain/admin.dart';
import 'package:fitness_app/state/app_state.dart';

class _FakeViolations implements ViolationSource {
  final Map<String, int> counts = {};
  final List<String> writes = [];
  bool throwOnRead = false;
  bool throwOnWrite = false;

  @override
  Future<int> countOf(String uid) async {
    if (throwOnRead) throw StateError('permission-denied');
    return counts[uid] ?? 0;
  }

  @override
  Future<int> increment(String uid, {required String name}) async {
    if (throwOnWrite) throw StateError('permission-denied');
    writes.add(uid);
    return counts[uid] = (counts[uid] ?? 0) + 1;
  }
}

({AppState s, _FakeViolations src}) _admin() {
  final src = _FakeViolations();
  final s = AppState(demo: false)
    ..myUid = 'u-me'
    ..displayName = '阿健'
    ..violationSource = src;
  s.applyAdminClaim(true);
  return (s: s, src: src);
}

ReportCase _case({String? accusedUid = 'u-阿昶'}) => ReportCase(
      id: 'R-1',
      targetKey: 'post:p1',
      target: ReportTarget.post,
      origin: CaseOrigin.userReport,
      content: '違規內容',
      reason: '不實內容',
      reporterCount: 1,
      accused: '阿昶',
      accusedUid: accusedUid,
      accusedViolations: 0,
      enteredAt: DateTime(2026, 9, 24),
      state: CaseState.reviewing,
    );

void main() {
  group('記點寫上雲', () {
    test('判成立 → 對方的違規次數加一', () async {
      final a = _admin();
      final c = _case();
      a.s.reports.add(c);

      a.s.upholdReport(c);
      await Future<void>.delayed(Duration.zero);

      expect(a.src.writes, ['u-阿昶']);
      expect(a.src.counts['u-阿昶'], 1);
    });

    test('一次裁決只記一點 —— 不是兩點', () async {
      final a = _admin();
      final c = _case();
      a.s.reports.add(c);

      a.s.upholdReport(c);
      await Future<void>.delayed(Duration.zero);

      // 初版本機加一次、雲端那支又加一次，一次裁決記成兩點。
      expect(a.s.violationsOf('阿昶'), 1);
      expect(a.src.counts['u-阿昶'], 1);
    });

    test('本機以雲端回來的數字為準 —— 兩位管理員同時裁決時本機會少算', () async {
      final a = _admin();
      a.src.counts['u-阿昶'] = 7; // 別人剛剛也判了幾次
      final c = _case();
      a.s.reports.add(c);

      a.s.upholdReport(c);
      await Future<void>.delayed(Duration.zero);

      expect(a.s.violationsOf('阿昶'), 8, reason: '不是本機推算的 1');
    });

    test('駁回不記點', () async {
      final a = _admin();
      final c = _case();
      a.s.reports.add(c);

      a.s.dismissReport(c);
      await Future<void>.delayed(Duration.zero);

      expect(a.src.writes, isEmpty);
    });

    test('舊案件沒有 uid → 記不了點，但本機仍然記著這一次', () async {
      final a = _admin();
      final c = _case(accusedUid: null);
      a.s.reports.add(c);

      a.s.upholdReport(c);
      await Future<void>.delayed(Duration.zero);

      // 寫到暱稱底下的話，改名就斷了、撞名就記到別人頭上 ——
      // 記錯人比不記更糟。
      expect(a.src.writes, isEmpty);
      expect(a.s.violationsOf('阿昶'), 1, reason: '本機這一次還是要算');
    });

    test('寫不上去不會把本機那一次吃掉', () async {
      final a = _admin()..src.throwOnWrite = true;
      final c = _case();
      a.s.reports.add(c);

      a.s.upholdReport(c);
      await Future<void>.delayed(Duration.zero);

      expect(a.s.violationsOf('阿昶'), 1);
    });
  });

  group('自己的次數要讀回來', () {
    test('登入時從雲端讀，不從存檔讀', () async {
      final a = _admin();
      a.src.counts['u-me'] = 3;

      await a.s.loadMyViolations();

      // 存檔是本人寫得動的，而處罰級距靠這個數字決定。
      expect(a.s.myViolations, 3);
    });

    test('沒有紀錄＝沒有違規過', () async {
      final a = _admin();
      await a.s.loadMyViolations();
      expect(a.s.myViolations, 0);
    });

    test('讀不到就維持現狀 —— 往少的方向錯，不往多的方向錯', () async {
      final a = _admin();
      a.s.myViolations = 2;
      a.src.throwOnRead = true;

      await a.s.loadMyViolations();

      expect(a.s.myViolations, 2, reason: '讀不到而多罰，比讀不到而少罰糟');
    });

    test('沒接雲端就什麼都不做', () async {
      final s = AppState(demo: false)..myUid = 'u-me';
      await s.loadMyViolations();
      expect(s.myViolations, 0);
    });
  });
}
