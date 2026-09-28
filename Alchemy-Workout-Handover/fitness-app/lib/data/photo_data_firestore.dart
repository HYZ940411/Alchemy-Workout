import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/photo.dart';
import 'photo_data.dart';

/// Firestore 上的照片。
///
/// ```
/// post_photos/{photoId}   bytes（Blob）、ownerUid、createdAt
/// ```
///
/// 安全規則：**登入者皆可讀**（貼文本來就是公開的），
/// **只有本人能建立**，而且**不可修改** —— 照片換掉等於偷換別人看過的
/// 內容，那不該發生在一個貼文系統裡（見 `firestore.rules`）。
///
/// 存 `Blob` 而不是 base64 字串：base64 會膨脹 33%，
/// 而我們正好卡在文件大小的上限附近。
class FirestorePhotos implements PhotoSource {
  final String uid;
  final FirebaseFirestore _db;

  /// 讀過的照片留在記憶體裡。
  ///
  /// **動態牆會反覆畫同一張圖** —— 捲動、重建、回到上一頁都會。
  /// 每一次都去 Firestore 拿的話，那是實打實的讀取次數
  /// （免費層每日五萬次），而位元組本身是不會變的（照片不可修改）。
  final _cache = <String, Uint8List?>{};

  FirestorePhotos({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('post_photos');

  @override
  Future<String> put(Uint8List bytes) async {
    if (bytes.length > kMaxPhotoBytes) {
      // 到這裡還超標代表壓縮那一層沒做好。**當場講出來** ——
      // 讓它繼續走下去的話，錯誤會變成 Firestore 的寫入拒絕，
      // 而那個訊息看不出是照片太大。
      throw ArgumentError('照片未壓縮：${bytes.length} 位元組');
    }
    final doc = _col.doc();
    final id = '$kPhotoIdPrefix${doc.id}';
    await _col.doc(doc.id).set({
      'bytes': Blob(bytes),
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _cache[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> get(String id) async {
    if (_cache.containsKey(id)) return _cache[id];
    if (!isUploadedPhoto(id)) return null;
    try {
      final snap = await _col.doc(id.substring(kPhotoIdPrefix.length)).get();
      final raw = snap.data()?['bytes'];
      final out = raw is Blob ? raw.bytes : null;
      // **連「找不到」也快取。** 不然一張被刪掉的照片會在每次重畫時
      // 再查一次，而它永遠不會出現。
      _cache[id] = out;
      return out;
    } catch (_) {
      // 讀不到照片不該擋住動態牆 —— 畫面自己會顯示破圖佔位。
      return null;
    }
  }
}
