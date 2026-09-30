// 存檔寫出去的每個鍵都要有人讀回來（2026-09-24）。
//
// ## 這道檢查抓的是什麼
//
// 存檔是一份「寫」與一份「讀」，兩邊各自維護。加欄位時很容易只改一邊：
//
//   · **寫了沒讀** → 資料存進去了，重開卻沒套用。看起來像「沒存到」。
//   · **讀了沒寫** → 讀取器等著一個永遠不會出現的鍵，預設值靜靜生效。
//
// 第二種在這個專案真的發生過，而且不可回復：`MailReward` 由「存一句
// 顯示文字」改為「存數額」時沒升版本號，舊存檔的 `content` 被新讀取器
// 忽略、四個數額欄位各自預設為 0，下一次自動存檔再把 0 寫回去 ——
// **信箱裡的獎勵被靜默清空**。那次之後才有了 `kSnapshotVersion` 的規矩。
//
// ## 這道檢查**抓不到**什麼
//
// **欄位兩邊都沒有。** 2026-09-24 使用者回報「新手任務的訓練時段跟評分
// 都沒有上雲」—— `preferredTimes` 與 `experienceRatings` 在這個檔案裡
// 是零筆引用，寫與讀兩邊都沒有，所以完美對稱，這條測試一片綠。
//
// 那一類要靠 `persistence_test` 的存讀一輪去釘，**一個欄位一條**。
// 別把這條當護身符。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 只寫不讀是對的那些鍵。**每一筆都要寫理由。**
const _writeOnly = <String, String>{
  'savedAt': '診斷用的時間戳，給人看的，不套回狀態',
};

/// 只讀不寫是對的那些鍵：**舊存檔的欄位，讀進來翻成新的，不再寫回去。**
///
/// 每一筆都要寫「舊的是什麼、新的是哪一個」，否則一個打錯字的鍵
/// 混進來就會永遠躲過上面那道檢查。
const _legacyRead = <String, String>{
  'following': '暱稱重構階段三：改存鍵，新欄位 followingKeys',
  'followers': '暱稱重構階段三：改存鍵，新欄位 followerKeys',
};

void main() {
  test('存檔的寫與讀兩邊對得上', () {
    final src =
        File('lib/state/app_state_snapshot.dart').readAsStringSync();
    final i = src.indexOf('Map<String, dynamic> toSnapshot()');
    final j = src.indexOf('bool applySnapshot(');
    expect(i, isNot(-1));
    expect(j, greaterThan(i), reason: '這兩支的順序變了，下面的切法要跟著改');

    // 巢狀的鍵也算 —— 每筆紀錄自己的欄位同樣是寫讀兩邊要對上的東西。
    final written = RegExp(r"'([A-Za-z_]\w*)'\s*:")
        .allMatches(src.substring(i, j))
        .map((m) => m.group(1)!)
        .toSet();
    final read = RegExp(r"'([A-Za-z_]\w*)'")
        .allMatches(src.substring(j))
        .map((m) => m.group(1)!)
        .toSet();

    // 抓不到任何鍵＝正則失效了。那比漏抓更糟：它會讓這道檢查
    // 永遠是綠的，而沒有人會發現（守則第 2 條）。
    expect(written.length, greaterThan(50),
        reason: '存檔的寫法變了，這條測試的正則要跟著更新');

    expect(
      written.difference(read).difference(_writeOnly.keys.toSet()),
      isEmpty,
      reason: '這些鍵存進去了卻沒有人讀回來 —— 重開 App 就等於沒存。\n'
          '確認過真的只寫不讀，再加進 _writeOnly 並寫上理由。',
    );

    expect(
      read.difference(written).difference(_legacyRead.keys.toSet()),
      isEmpty,
      reason: '讀取器在等一個永遠不會被寫出去的鍵，預設值會靜靜生效。\n'
          '信箱獎勵被清空那次就是這樣來的。',
    );
  });
}
