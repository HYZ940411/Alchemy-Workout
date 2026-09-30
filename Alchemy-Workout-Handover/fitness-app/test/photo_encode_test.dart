// 上傳的照片一定要塞得進 Firestore 的單一文件。
//
// 2026-09-28 使用者裁決：照片存 Firestore，不另外開 Cloudflare R2
// （「所以為什麼上傳個圖片需要那麼麻煩？不能簡單化嗎？」）。
//
// 那個決定把「檔案多大」從一個效能問題變成**正確性問題**：
// 超過 1 MiB 的文件 Firestore 直接拒收，整筆寫入失敗。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/domain/photo.dart';

/// 造一張有雜訊的圖 —— 純色圖 JPEG 壓完只有幾 KB，測不出上限。
Uint8List noisyJpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  var seed = 1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      im.setPixelRgb(x, y, seed & 0xff, (seed >> 8) & 0xff, (seed >> 16) & 0xff);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 100));
}

void main() {
  test('長邊縮到 1024 以內', () {
    final out = encodePhoto(noisyJpeg(3000, 2000))!;
    expect(out.width, kMaxPhotoEdge);
    expect(out.height, lessThanOrEqualTo(kMaxPhotoEdge));
  });

  test('直式照片縮的是高，不是寬', () {
    final out = encodePhoto(noisyJpeg(1200, 2400))!;
    expect(out.height, kMaxPhotoEdge);
    expect(out.width, lessThan(kMaxPhotoEdge));
  });

  test('本來就小的圖不放大', () {
    final out = encodePhoto(noisyJpeg(300, 200))!;
    expect(out.width, 300);
    expect(out.height, 200);
  });

  test('高雜訊的大圖也壓得進上限', () {
    final out = encodePhoto(noisyJpeg(4000, 3000))!;
    expect(out.bytes.length, lessThanOrEqualTo(kMaxPhotoBytes));
  });

  test('上限留了餘裕，不貼著 Firestore 的 1 MiB 天花板', () {
    expect(kMaxPhotoBytes, lessThan(1024 * 1024),
        reason: '同一份文件還有 ownerUid、時間戳與欄位名稱');
  });

  test('不是圖片的檔案回空值，不丟例外', () {
    // 使用者選錯檔案是家常便飯，那不是程式錯誤。
    expect(encodePhoto(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    expect(encodePhoto(Uint8List(0)), isNull);
  });

  group('上傳的照片與內建圖庫分得出來', () {
    test('上傳的照片', () {
      expect(isUploadedPhoto('${kPhotoIdPrefix}abc'), isTrue);
    });
    test('內建圖庫', () {
      expect(isUploadedPhoto('im_barbell'), isFalse);
    });
  });
}
