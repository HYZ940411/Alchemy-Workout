// 服務條款與隱私權政策（`[QA-02k]`）。
//
// 原本這一頁只有一段文字：五條路徑的訓練免責聲明。那是規格明訂**必須**
// 有的（〈註冊流程〉2026-08-20 由三條擴充為五條），但一份要讓人按下
// 「我已閱讀並同意」的條款，只有免責是不夠的。
//
// 2026-09-18 由使用者提供完整草稿，合併進來。**兩處刻意與草稿不同**，
// 這份測試把那兩處釘住 —— 它們是最容易在日後被「修回去」的地方。

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/domain/registration.dart';

String get _all => kTermsSections.map((s) => '${s.$1}\n${s.$2}').join('\n');

void main() {
  group('與規格衝突的兩處，改的是條款不是規格', () {
    test('年齡下限寫 13 歲，不是 16 歲', () {
      // 草稿寫 16。〈註冊流程〉2026-08-19 有一條 [決策] 明確駁回 16 歲：
      // 會排除 13–15 歲使用者，並作廢〈13 歲沿用 14 歲的係數〉。
      // 條款與 kMinAge 不能各說一套。
      expect(_all, contains('未滿 13 歲'));
      expect(_all, isNot(contains('未滿 16 歲')));
      expect(kMinAge, 13, reason: '條款講的數字要跟程式擋的數字是同一個');
    });

    test('審核不承諾具體時數', () {
      // 草稿寫「24 小時內審核」。但〈審核時限設定〉的初始值是
      // 檢舉 7 天、申訴 72 小時，而且那四項是**後台可調參數** ——
      // 條款寫死一個數字，等於承諾了平台做不到、而且隨時會變的事。
      expect(_all, isNot(contains('24 小時')));
      expect(_all, contains('依內部審核流程'));
    });
  });

  group('規格明訂必須有的內容', () {
    test('訓練免責涵蓋五條路徑，一條都不能少', () {
      // 〈註冊流程〉2026-08-20 由三條擴充為五條，兩條擴充各有裁決理由。
      for (final path in [
        '教官的回答',
        '師徒任務的內容',
        '其他使用者公開的課表',
        'AI 訓練建議',
        '平台動作示範內容',
      ]) {
        expect(_all, contains(path), reason: '免責路徑「$path」不見了');
      }
    });

    test('隱私條文講得出資料存在哪裡、留多久、怎麼刪', () {
      expect(_all, contains('Firebase'), reason: '要講得出存在哪裡');
      expect(_all, contains('30 天'), reason: '刪除的冷靜期');
      expect(_all, contains('檢舉'), reason: '刪除的例外要告知');
    });

    test('條款改版須重新同意這件事本身要寫在條款裡', () {
      expect(_all, contains('重新同意'));
    });
  });

  test('改了條文就要動版本號', () {
    // 這條擋的是「改了字卻忘了升版」—— 規格要求改版後既有使用者
    // 須重新同意，而判定的依據就是這個版本號。
    expect(SignUpDraft().termsVersion, 'v4.0');
  });
}
