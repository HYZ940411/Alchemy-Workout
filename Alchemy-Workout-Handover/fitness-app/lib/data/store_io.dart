import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// 這個平台的預設儲存後端。
///
/// 由 [store.dart] 以條件匯入挑選：有 `dart:io` 的平台（iOS／Android／
/// 桌面）走這裡，瀏覽器走 [store_web.dart]。**條件匯入的重點不是方便，
/// 是讓 `dart:io` 根本不會進到 Web 的編譯單元** —— 直接 import 的話，
/// Web 版連編都編不起來。
Store createStore() => FileStore();

/// 裝置層的小記事本，**不綁 uid** —— 登入頁要在還不知道使用者是誰的
/// 時候，回答「這台裝置登入過嗎」。
Store createDeviceStore() => FileStore(fileName: 'device.json');

Store createPlatformCacheStore() => FileStore(fileName: 'platform_cache.json');

/// 本機檔案。寫在系統的「應用程式文件」目錄，重開機仍在。
///
/// **先寫暫存檔再改名**：直接覆寫時，若寫到一半就被關掉，
/// 留下的是一個半截的 JSON —— 下次開啟解析失敗，等於整份進度不見。
/// 改名在同一個檔案系統上是原子操作，不會有中間狀態。
class FileStore implements Store {
  final String fileName;

  /// 存檔目錄。預設為系統的應用程式文件目錄；
  /// 測試傳一個暫存目錄進來，才驗得到真正跑在使用者機器上的這一份實作。
  final Future<Directory> Function()? directory;

  FileStore({this.fileName = 'state.json', this.directory});

  File? _cached;

  Future<File> _file() async {
    final dir = await (directory?.call() ?? getApplicationDocumentsDirectory());
    return _cached ??= File('${dir.path}/$fileName');
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    final f = await _file();
    if (!await f.exists()) return null; // 沒存過

    String text;
    try {
      text = await f.readAsString();
    } catch (e) {
      throw StoreLoadException('存檔讀不出來（$e）');
    }
    if (text.trim().isEmpty) return null; // 空檔等同沒存過

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('內容不是一份存檔');
      }
      return decoded;
    } catch (e) {
      // **不直接刪掉**：壞掉的存檔仍可能救得回來，而且使用者有權知道
      // 他的東西被搬到哪去了，不是被系統靜靜清掉。
      final backup = await _backUpBadFile(f);
      throw StoreLoadException('存檔內容壞掉了（$e）', backupPath: backup);
    }
  }

  /// 把壞掉的存檔改名保留。回傳新的路徑；改名失敗回傳空值。
  Future<String?> _backUpBadFile(File f) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final to = '${f.path}.bad.$stamp';
      await f.rename(to);
      return to;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

