// 上傳照片：壓縮 → 存 Firestore → 畫出來。
//
// 2026-09-28 使用者裁決 A。原本的計畫是 Cloudflare R2，但那要先在
// dashboard 走一次訂閱結帳 —— 使用者的原話是「所以為什麼上傳個圖片
// 需要那麼麻煩？不能簡單化嗎？」。他是對的：這個專案已經有一個存得下
// 東西的地方（Firestore），不必為了一張照片再辦一個服務。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/data/photo_data.dart';
import 'package:fitness_app/design/image_library.dart';
import 'package:fitness_app/domain/photo.dart';
import 'package:fitness_app/domain/platform_config.dart';
import 'package:fitness_app/screens/social/compose_post_screen.dart';
import 'package:fitness_app/state/app_state.dart';
import 'package:fitness_app/widgets/image_picker_sheet.dart';

/// 記憶體版的照片儲存。
class FakePhotos implements PhotoSource {
  final store = <String, Uint8List>{};
  int puts = 0;
  bool failPut = false;

  @override
  Future<String> put(Uint8List bytes) async {
    puts++;
    if (failPut) throw StateError('雲端掛了');
    final id = '$kPhotoIdPrefix${store.length}';
    store[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> get(String id) async => store[id];
}

Uint8List somePhoto({int w = 1600, int h = 1200}) {
  final im = img.Image(width: w, height: h);
  var seed = 7;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      im.setPixelRgb(x, y, seed & 0xff, (seed >> 8) & 0xff, (seed >> 16) & 0xff);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  setUp(platformConfig.reset);
  tearDown(platformConfig.reset);

  group('兩處的 ID 前綴必須一致', () {
    // 設計層不 import domain（相依方向會反過來），所以那三個字元各寫了
    // 一次。**兩份寫法的東西遲早會分家** —— 這條就是防它。
    test('domain 與畫面認的是同一個前綴', () {
      expect(kPhotoIdPrefixInUi, kPhotoIdPrefix);
    });

    test('兩邊的判定對同一個 ID 給同一個答案', () {
      for (final id in ['${kPhotoIdPrefix}x', 'im_barbell', '', 'ph', 'phx_1']) {
        expect(isUploadedPhotoId(id), isUploadedPhoto(id), reason: id);
      }
    });
  });

  group('上傳', () {
    test('沒接雲端時說得出來，不是默默失敗', () async {
      final s = AppState();
      expect(s.canUploadPhoto, isFalse);
      final (id, why) = await s.uploadPhoto(somePhoto());
      expect(id, isNull);
      expect(why, isNotNull);
    });

    test('存進去的是壓縮過的位元組，不是原檔', () async {
      final s = AppState()..photoSource = FakePhotos();
      final raw = somePhoto();
      final (id, why) = await s.uploadPhoto(raw);
      expect(why, isNull);
      expect(id, isNotNull);

      final saved = (s.photoSource as FakePhotos).store[id]!;
      expect(saved.length, lessThan(raw.length), reason: '沒壓就白做了');
      expect(saved.length, lessThanOrEqualTo(kMaxPhotoBytes));
    });

    test('不是圖片的檔案不會被送上雲端', () async {
      final fake = FakePhotos();
      final s = AppState()..photoSource = fake;
      final (id, why) = await s.uploadPhoto(Uint8List.fromList([9, 9, 9]));
      expect(id, isNull);
      expect(why, contains('圖片'));
      expect(fake.puts, 0, reason: '解不開就不該浪費一次寫入');
    });

    test('雲端失敗時回得出原因，不丟例外', () async {
      final s = AppState()..photoSource = (FakePhotos()..failPut = true);
      final (id, why) = await s.uploadPhoto(somePhoto());
      expect(id, isNull);
      expect(why, contains('失敗'));
    });

    test('拿得回來', () async {
      final s = AppState()..photoSource = FakePhotos();
      final (id, _) = await s.uploadPhoto(somePhoto());
      expect(await s.photoBytes(id!), isNotNull);
    });

    test('內建圖庫的 ID 不會跑去雲端查', () async {
      final fake = FakePhotos();
      final s = AppState()..photoSource = fake;
      expect(await s.photoBytes('im_barbell'), isNull);
    });
  });

  group('畫面', () {
    testWidgets('上傳的照片畫得出來', (t) async {
      final s = AppState()..photoSource = FakePhotos();
      final (id, _) = await s.uploadPhoto(somePhoto(w: 200, h: 200));

      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(home: Scaffold(body: AppImageView(id: id!))),
      ));
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('照片不見時顯示佔位，不是一片空白也不是當掉', (t) async {
      final s = AppState()..photoSource = FakePhotos();
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: Scaffold(body: AppImageView(id: '${kPhotoIdPrefix}missing')),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('沒接雲端時，選圖抽屜不出現「從裝置選擇照片」', (t) async {
      final s = AppState();
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: ElevatedButton(
                onPressed: () => pickImages(c,
                    title: '選圖', selected: const [], showLibrary: true),
                child: const Text('開'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('開'));
      await t.pumpAndSettle();
      expect(find.text('從裝置選擇照片'), findsNothing);
    });

    testWidgets('接了雲端就出現', (t) async {
      final s = AppState()..photoSource = FakePhotos();
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: ElevatedButton(
                onPressed: () => pickImages(c,
                    title: '選圖', selected: const [], showLibrary: true),
                child: const Text('開'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('開'));
      await t.pumpAndSettle();
      expect(find.text('從裝置選擇照片'), findsOneWidget);
    });
  });

  group('內建圖庫只留在後台（1G，2026-09-29 使用者裁決 A）', () {
    /// 開一個只有一顆按鈕的畫面，按下去打開選圖抽屜。
    ///
    /// 不直接建 `_ImagePicker` —— 那是私有的，而且真正要驗的是
    /// **呼叫端傳什麼、抽屜就長什麼樣**。
    Future<void> openSheet(
      WidgetTester t,
      AppState s, {
      required bool showLibrary,
    }) async {
      await t.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: ElevatedButton(
                onPressed: () => pickImages(c,
                    title: '選圖', selected: const [], showLibrary: showLibrary),
                child: const Text('開'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('開'));
      await t.pumpAndSettle();
    }

    // 拿第一張圖的標籤當標記。用標籤而不是 ID：ID 是內部的，
    // 而使用者看到的是「訓練上衣」這四個字。
    final firstLabel = kImageLibrary.first.label;

    testWidgets('showLibrary: false —— 內建的假照片一張都不出現', (t) async {
      await openSheet(t, AppState()..photoSource = FakePhotos(),
          showLibrary: false);
      expect(find.text(firstLabel), findsNothing);
      expect(find.text('或從下面的內建圖片挑：'), findsNothing);
      // 真的上傳那條路還在。
      expect(find.text('從裝置選擇照片'), findsOneWidget);
    });

    testWidgets('showLibrary: true —— 後台仍挑得到', (t) async {
      await openSheet(t, AppState(), showLibrary: true);
      expect(find.text(firstLabel), findsOneWidget);
    });

    testWidgets('兩條路都沒有時，抽屜要說得出話 —— 不留一個空白面板', (t) async {
      await openSheet(t, AppState(), showLibrary: false);
      expect(find.text(firstLabel), findsNothing);
      expect(find.textContaining('目前無法加入圖片'), findsOneWidget);
    });

    testWidgets('發文頁：沒接雲端就不放那顆按鈕', (t) async {
      await t.pumpWidget(AppScope(
        state: AppState(),
        child: const MaterialApp(home: ComposePostScreen()),
      ));
      await t.pumpAndSettle();
      expect(find.text('加入圖片'), findsNothing,
          reason: '打開來是空的按鈕不如不放');
    });

    testWidgets('發文頁：接了雲端才放，而且打開沒有假照片', (t) async {
      await t.pumpWidget(AppScope(
        state: AppState()..photoSource = FakePhotos(),
        child: const MaterialApp(home: ComposePostScreen()),
      ));
      await t.pumpAndSettle();
      expect(find.text('加入圖片'), findsOneWidget);
      await t.tap(find.text('加入圖片'));
      await t.pumpAndSettle();
      expect(find.text(firstLabel), findsNothing,
          reason: '這一條是使用者 2026-09-28 指出的那件事');
    });
  });

  // App 那一側壓過一次，但那是客戶端的程式碼，改得掉。
  // 安全規則是改不掉的那一道 —— 兩個數字要對得上。
  test('安全規則的大小上限與壓縮上限是同一個數字', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('post_photos'));
    expect(rules, contains('$kMaxPhotoBytes'),
        reason: 'firestore.rules 的 bytes.size() 上限要等於 kMaxPhotoBytes');
    expect(rules, contains('allow update: if false'),
        reason: '照片不可修改 —— 換掉等於偷換別人看過的內容');
  });
}
