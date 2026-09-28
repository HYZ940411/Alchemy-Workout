/// 使用者上傳的照片：縮到存得下的大小。
///
/// ## 為什麼是自己重新編碼，而不是信任選檔器
///
/// `image_picker` 有 `maxWidth` / `imageQuality` 參數，但各平台的實作
/// 不一樣（Web 走 canvas、行動端走原生）。**這裡的上限是硬性的** ——
/// Firestore 單一文件最多 1 MiB，超過就整筆寫入失敗。
/// 讓三個平台各自決定壓多少，等於讓「存不存得進去」看平台臉色。
///
/// 所以不管選檔器回什麼，一律自己解碼、縮邊、重編 JPEG，
/// 而且**編完會量一次大小**，太大就降品質再來一次。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 長邊上限。1024 對手機螢幕綽綽有餘，而它決定了檔案大小的量級。
const kMaxPhotoEdge = 1024;

/// 單張照片的位元組上限。
///
/// Firestore 的文件上限是 **1 MiB（1,048,576 位元組）**，但那是**整份文件**
/// 的上限，不是單一欄位 —— 同一份文件還有 ownerUid、時間戳與欄位名稱本身。
/// 所以留 15% 餘裕，不要貼著天花板寫。
const kMaxPhotoBytes = 890 * 1024;

/// 依序嘗試的 JPEG 品質。第一個就夠小的話不會再往下走。
const _qualities = [82, 70, 58, 45, 32];

/// 上傳照片的 ID 前綴。內建圖庫是 `im_`，兩者要分得出來 ——
/// 畫面依這個決定「查圖庫」還是「去雲端拿位元組」。
const kPhotoIdPrefix = 'ph_';

bool isUploadedPhoto(String id) => id.startsWith(kPhotoIdPrefix);

/// 壓縮結果。[bytes] 保證不超過 [kMaxPhotoBytes]。
class EncodedPhoto {
  final Uint8List bytes;
  final int width;
  final int height;

  /// 最後用的 JPEG 品質。**診斷用** —— 品質掉到最低還是很大的照片，
  /// 多半是尺寸極端的圖（例如很長的截圖），看得到才查得出來。
  final int quality;

  const EncodedPhoto(this.bytes, this.width, this.height, this.quality);
}

/// 解不開的檔案（不是圖、或格式不支援）時回傳空值。
///
/// **不丟例外**：使用者選錯檔案是家常便飯，那不是程式錯誤。
/// 呼叫端負責講一句聽得懂的話。
EncodedPhoto? encodePhoto(Uint8List raw) {
  // **`decodeImage` 對垃圾輸入是丟例外，不是回空值。**
  // 測試餵了五個位元組進去，拿到的是 `RangeError (length)` ——
  // 那會一路炸到畫面上，而使用者只是選錯了檔案。
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;

  // 只縮不放 —— 小圖放大只會變大又變糊。
  final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
  final resized = longest > kMaxPhotoEdge
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? kMaxPhotoEdge : null,
          height: decoded.height > decoded.width ? kMaxPhotoEdge : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;

  Uint8List? last;
  var lastQuality = _qualities.last;
  for (final q in _qualities) {
    final out = img.encodeJpg(resized, quality: q);
    last = out;
    lastQuality = q;
    if (out.length <= kMaxPhotoBytes) {
      return EncodedPhoto(out, resized.width, resized.height, q);
    }
  }

  // 每一種品質都還是太大 —— 再把邊長砍半，遞迴一次。
  // **有終止條件**：邊長每次減半，小到 64 就放棄。
  if (resized.width > 64 && resized.height > 64) {
    final half = img.copyResize(resized, width: resized.width ~/ 2);
    return encodePhoto(img.encodeJpg(half, quality: _qualities.first));
  }
  // 縮到 64 還塞不下的圖不存在於現實，但不要回一個超標的東西 ——
  // 那會變成雲端的寫入失敗，而失敗點離原因很遠。
  return last != null && last.length <= kMaxPhotoBytes
      ? EncodedPhoto(last, resized.width, resized.height, lastQuality)
      : null;
}
