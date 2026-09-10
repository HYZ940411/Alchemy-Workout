import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/state/app_state.dart';

void main() {
  group('限時任務未領取者，當日結束補發至信箱', () {
    AppState done() {
      final s = AppState();
      s.completeTimedTask();
      expect(s.canClaimTimedReward, isTrue);
      return s;
    }

    test('跨日時掃進信箱，不作廢', () {
      final s = done();
      final n = s.mailbox.length;
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.mailbox.length, n + 1);
      expect(s.mailbox.first.source, contains('限時任務'));
      expect(s.mailbox.first.claimed, isFalse);
    });

    test('已領取者不重複補發', () {
      final s = done();
      s.claimTimedReward();
      final n = s.mailbox.length;
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.mailbox.length, n);
    });

    test('沒完成任務就沒有東西可補發', () {
      final s = AppState();
      expect(s.canClaimTimedReward, isFalse);
      final n = s.mailbox.length;
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.mailbox.length, n);
    });

    test('限時任務每日換一組：指派日往前滾，完成紀錄歸零', () {
      final s = done();
      expect(s.timedTaskExpired, isFalse);
      s.advanceDemoClock(const Duration(days: 1));
      expect(s.timedTaskExpired, isFalse, reason: '新的一天有新的一組');
      expect(s.timedTask.doneBy(s.displayName), isFalse,
          reason: '前一日的不可補做，兩組疊在一起「限時」就沒意義了');
      expect(s.canClaimTimedReward, isFalse);
      expect(s.myTeam!.timedCredited, isEmpty,
          reason: '團隊的當日完成紀錄不跨週期保留');

      // 新的一天重新完成，獎勵要領得到 —— 領取旗標沒歸零的話，
      // 昨天領過的人今天就再也領不到。
      s.completeTimedTask();
      expect(s.canClaimTimedReward, isTrue);
      expect(s.claimTimedReward(), isNotNull);
    });
  });

  group('單位偏好真的影響顯示', () {
    test('公制與英制各自換算', () {
      final s = AppState();
      expect(s.weightText(70), '70.0 kg');
      expect(s.heightText(175), '175 cm');
      expect(s.loadText(62.5), '62.5 kg');
      expect(s.loadText(0), '徒手');

      s.setFlag(metric: false);
      expect(s.weightText(70), '154.3 lb');
      expect(s.heightText(175), '68.9 in');
      expect(s.loadText(62.5), '137.8 lb');
      expect(s.loadText(0), '徒手', reason: '徒手不帶單位');
    });

    test('僅影響顯示，不影響儲存', () {
      final s = AppState();
      final kg = s.bodyweightKg;
      s.setFlag(metric: false);
      expect(s.bodyweightKg, kg, reason: '一律以公制儲存');
    });

    test('英制範圍由公制換算而來', () {
      final s = AppState()..setFlag(metric: false);
      expect(double.parse(s.heightDisplay(50).$1), closeTo(19.7, 0.1));
      expect(double.parse(s.heightDisplay(250).$1), closeTo(98.4, 0.1));
      expect(double.parse(s.weightDisplay(20).$1), closeTo(44.1, 0.1));
      expect(double.parse(s.weightDisplay(300).$1), closeTo(661.4, 0.1));
    });

    test('訓練量同樣跟著換算', () {
      final s = AppState();
      expect(s.volumeDisplay(1000), ('1000', 'kg'));
      s.setFlag(metric: false);
      expect(s.volumeDisplay(1000).$2, 'lb');
    });
  });

  group('電子郵件為選填，填得了也清得掉', () {
    test('預設未填', () {
      final s = AppState();
      expect(s.email, isNull);
      expect(s.emailNotifiable, isFalse);
    });

    test('填入後，三類通知的分支才走得到', () {
      final s = AppState();
      expect(s.setEmail('a@b.com'), isNull);
      expect(s.email, 'a@b.com');
      expect(s.emailNotifiable, isTrue);
    });

    test('格式不對就擋下，且不寫入', () {
      final s = AppState();
      expect(s.setEmail('沒有小老鼠'), isNotNull);
      expect(s.email, isNull);
      expect(s.setEmail('a@b'), isNotNull);
      expect(s.email, isNull);
    });

    test('空白視為清空，是合法操作', () {
      final s = AppState();
      s.setEmail('a@b.com');
      expect(s.setEmail('   '), isNull);
      expect(s.email, isNull, reason: '選填欄位要能改回未填');
    });

    test('前後空白會被去掉', () {
      final s = AppState();
      s.setEmail('  a@b.com  ');
      expect(s.email, 'a@b.com');
    });
  });
}
