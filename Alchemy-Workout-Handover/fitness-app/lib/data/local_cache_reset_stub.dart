import 'package:cloud_firestore/cloud_firestore.dart';

/// 非 Web 平台：快取在 App 沙盒裡，登出不需要清，也沒有「重新載入頁面」這回事。
Future<void> wipeLocalCacheAndReload(FirebaseFirestore db) async {}
