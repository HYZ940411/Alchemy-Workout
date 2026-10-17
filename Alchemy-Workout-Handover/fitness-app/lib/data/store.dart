import 'dart:convert';

// 條件匯入：有 `dart:io` 的平台（iOS／Android／桌面）拿到檔案版，
// 瀏覽器拿到 localStorage 版。兩邊各自 export 一個 `createStore()`。
//
// 這樣寫的理由不是方便，是**讓平台專屬的匯入不進到另一邊的編譯單元** ——
// `dart:io` 只要出現在 Web 編得到的地方，Web 版就編不起來。
import 'store_io.dart' if (dart.library.js_interop) 'store_web.dart' as impl;

/// 這台裝置上的預設儲存後端。
///
/// [main] 只認這一個函式，不知道自己跑在哪個平台上。
Store defaultStore() => impl.createStore();

/// 這台裝置的小記事本。**與使用者無關**，只記得住跨帳號都成立的事。
///
/// 目前只放一件事：這台裝置成功登入過。登入頁在還不知道使用者是誰的
/// 時候需要它 —— 對已經有帳號的人說「選一種方式**建立帳號**」，
/// 第一個感覺是「我以前註冊過卻忘了？」。
Store deviceStore() => impl.createDeviceStore();

/// 平台資料的本機快取（見 `platform_cache.dart`）。**不綁 uid**：平台資料是全站公用的。
Store platformCacheStore() => impl.createPlatformCacheStore();

/// 這台裝置成功登入過沒有。讀不出來一律當作沒有 ——
/// 猜錯的方向要選傷害小的那一邊：對老手說「開始吧」只是囉嗦，
/// 對新手說「歡迎回來」會讓他以為自己忘了舊帳號。
Future<bool> hasSignedInBefore(Store s) async {
  try {
    return (await s.load())?['signedIn'] == true;
  } catch (_) {
    return false;
  }
}

Future<void> markSignedIn(Store s) => s.save({'signedIn': true});

/// 存讀的邊界。
///
/// App 其餘部分只認這個介面，不知道資料實際上放在哪 ——
/// 日後改為打後端 API，換掉一個實作即可，[AppState] 一行都不用動。
///
/// 三個方法皆為整份快照的存讀，不做逐欄位更新：本專案的狀態全在記憶體，
/// 逐欄位同步只會讓「哪些欄位還沒寫進去」變成新的一類 bug。
abstract class Store {
  /// 回傳 null 表示**沒存過**。
  ///
  /// 存檔存在但讀不出來時**必須丟 [StoreLoadException]**，不可回傳 null ——
  /// 「沒存過」與「存檔壞掉」是兩件完全不同的事：前者照常開始，
  /// 後者要告訴使用者，否則他看到的是「我的進度全部不見了」而毫無說明。
  Future<Map<String, dynamic>?> load();

  Future<void> save(Map<String, dynamic> data);
  Future<void> clear();
}

/// 存檔存在但讀不出來。
class StoreLoadException implements Exception {
  final String reason;

  /// 壞掉的原檔被移到哪裡。使用者要知道資料沒有被直接刪掉。
  final String? backupPath;

  const StoreLoadException(this.reason, {this.backupPath});

  @override
  String toString() => 'StoreLoadException: $reason';
}

/// 測試與示範用。行為與 [FileStore] 一致，只是不落地。
class MemoryStore implements Store {
  Map<String, dynamic>? _data;
  int saves = 0;

  /// 設定後，[load] 改為丟出這個錯誤 —— 用來驗「存檔壞掉」那條路徑。
  StoreLoadException? failWith;

  @override
  Future<Map<String, dynamic>?> load() async {
    final f = failWith;
    if (f != null) throw f;
    return _data;
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    saves++;
    // 深拷貝一份：直接存 reference 的話，呼叫端之後改了物件，
    // 這裡「已存的內容」會跟著變，測試就驗不出真正存了什麼。
    _data = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async => _data = null;
}
