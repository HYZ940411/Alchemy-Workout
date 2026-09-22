import 'dart:convert';

import 'package:web/web.dart' as web;

import 'store.dart';

/// 這個平台的預設儲存後端。見 [store.dart] 的條件匯入。
Store createStore() => WebStore();

/// 裝置層的小記事本，**不綁 uid** —— 登入頁要在還不知道使用者是誰的
/// 時候，回答「這台裝置登入過嗎」。
Store createDeviceStore() => WebStore(key: 'device.json');

/// 瀏覽器的 localStorage。
///
/// 與 [FileStore] 是同一份契約的兩個實作，行為要一致 ——
/// 只有這樣，「Web 版跟手機版表現不一樣」才不會變成一類永遠查不完的 bug。
/// 三件事特別要對齊：
///
/// 1. **沒存過回傳 null，存檔壞掉丟 [StoreLoadException]。** 兩者是完全
///    不同的事：前者照常開始，後者要告訴使用者，否則他看到的是
///    「我的進度全部不見了」而毫無說明。
/// 2. **壞掉的存檔不直接刪掉**，改名保留。檔案版搬去 `.bad.<時戳>`，
///    這裡搬去另一個 key。使用者有權知道東西被搬到哪，不是被靜靜清掉。
/// 3. **寫入要嘛整份成功、要嘛完全不動。** 檔案版靠「先寫暫存檔再改名」
///    取得原子性；localStorage 的 `setItem` 本身就是整份取代，
///    寫到一半不會留下半截的值。
///
/// **容量**：localStorage 每個來源約 5 MB。這份快照約 6 KB，差三個數量級。
/// 真的滿了 `setItem` 會丟 `QuotaExceededError` —— 那是 [save] 唯一的
/// 失敗模式，交給呼叫端處理，不在這裡吞掉。
class WebStore implements Store {
  /// 存放的鍵。與檔案版的 `state.json` 對應。
  final String key;

  WebStore({this.key = 'state.json'});

  /// 壞掉的存檔搬去哪。對應檔案版的 `.bad.<時戳>`。
  String _badKey(int stamp) => '$key.bad.$stamp';

  web.Storage get _s => web.window.localStorage;

  @override
  Future<Map<String, dynamic>?> load() async {
    final text = _s.getItem(key);
    if (text == null) return null; // 沒存過
    if (text.trim().isEmpty) return null; // 空值等同沒存過

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('內容不是一份存檔');
      }
      return decoded;
    } catch (e) {
      final backup = _backUpBadValue(text);
      throw StoreLoadException('存檔內容壞掉了（$e）', backupPath: backup);
    }
  }

  /// 把壞掉的值搬到另一個鍵。回傳新的鍵；搬不動回傳空值。
  ///
  /// 搬不動（例如空間已滿）時**原值留著不刪** —— 寧可下次再壞一次，
  /// 也不要為了清乾淨而把使用者唯一的一份資料丟掉。
  String? _backUpBadValue(String text) {
    final to = _badKey(DateTime.now().millisecondsSinceEpoch);
    try {
      _s.setItem(to, text);
      _s.removeItem(key);
      return to;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    _s.setItem(key, jsonEncode(data));
  }

  @override
  Future<void> clear() async {
    _s.removeItem(key);
  }
}
