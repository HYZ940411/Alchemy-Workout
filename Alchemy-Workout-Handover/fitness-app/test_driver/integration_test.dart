// integration_test 的驅動端：把 App 端截下來的圖寫成檔案。
//
// 截圖必須走這裡 —— App 跑在模擬器裡，寫不到 Mac 的檔案系統。
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final f = File('shots/$name.png');
      await f.create(recursive: true);
      await f.writeAsBytes(bytes);
      return true;
    },
  );
}
