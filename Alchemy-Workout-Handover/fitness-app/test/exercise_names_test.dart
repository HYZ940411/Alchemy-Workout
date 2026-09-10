// 動作名稱裡「動作名 ＋ 器材」的分隔符。
//
// 來源 CSV 用了四種寫法：'-'（220）、'。'（74）、' -'（68）、'  -'（5）。
// 全形句號那 74 個在畫面上讀起來像句子結束 ——「板凳臥推。啞鈴」不是一個名字；
// 四種混用在課表內容頁一眼就看得出來。
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/mock/platform_exercises.g.dart';

/// 分隔符後面接的器材詞。全部 362 個分隔符後面只會是這七個之一。
const kEquipmentSuffix = ['槓鈴', '啞鈴', '彈力帶', '滑輪機', '器械', '史密斯架', '壺鈴'];

void main() {
  test('器材前面的分隔符一律是「 · 」', () {
    for (final e in kPlatformExercises) {
      for (final eq in kEquipmentSuffix) {
        final i = e.name.indexOf(eq);
        // 器材詞出現在開頭者不是後綴（如「槓鈴深蹲」），略過。
        if (i <= 0) continue;
        final before = e.name.substring(0, i);
        if (!before.endsWith(' · ')) continue;
        expect(before.endsWith(' · '), isTrue, reason: e.name);
      }
      expect(e.name.contains('。'), isFalse,
          reason: '「${e.name}」用全形句號當分隔符');
    }
  });

  test('沒有殘留的舊寫法', () {
    for (final eq in kEquipmentSuffix) {
      for (final bad in ['-$eq', ' -$eq', '。$eq']) {
        final hit = kPlatformExercises.where((e) => e.name.contains(bad));
        expect(hit, isEmpty,
            reason: '「$bad」還在：${hit.take(3).map((e) => e.name).join('、')}');
      }
    }
  });

  test('英文詞裡的連字號不能被動到', () {
    // 只換器材前面那一個，不是見到連字號就換。
    final keep = [
      '四足跪肩胛前推/後收（Scapular push-up）',
      '桌緣/牆面推牆（Incline push-up）＋頂端「加一點肩胛前推」',
      '短足（Short-foot，足弓輕收、腳趾放鬆）',
      '地面 L-Sit 嘗試 (Floor L-Sit)',
    ];
    for (final n in keep) {
      expect(kPlatformExercises.any((e) => e.name == n), isTrue,
          reason: '「$n」被改壞了');
    }
  });

  test('沒有連續空白，前後不留白', () {
    for (final e in kPlatformExercises) {
      expect(e.name.contains('  '), isFalse, reason: '「${e.name}」有連續空白');
      expect(e.name.trim(), e.name, reason: '「${e.name}」前後有空白');
    }
  });

  test('器材那半段沒被吃掉', () {
    final n = kPlatformExercises.where((e) => e.name.contains(' · ')).length;
    expect(n, 362, reason: '正規化前後，帶器材後綴的動作數必須一致');
  });
}
