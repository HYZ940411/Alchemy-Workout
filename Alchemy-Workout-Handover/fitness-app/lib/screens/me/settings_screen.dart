import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../mock/mock_equipment.dart';
import '../../state/app_state.dart';
import '../train/preferred_times_screen.dart';
import 'account_delete_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Read Model：設定頁
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// 值域為〈器材設定 Aggregate〉的 8 個品項，與動作的「所需器材明細」同一組。
  static const _equipment = kEquipmentItems;

  /// 登出。
  ///
  /// **先補一次存檔再登出**：自動存檔有 300ms 防抖，登出當下若剛好還在
  /// 那個窗口裡，最後一筆變動會跟著登入狀態一起消失。
  ///
  /// **登出之後一定要把疊上去的畫面收掉。** [AuthGate] 換掉的是
  /// `MaterialApp.home`，也就是**最底層**那一頁；而設定頁是
  /// `Navigator.push` 疊在它上面的。只換底層的話，登入頁是畫出來了，
  /// 卻整個被設定頁蓋住 —— 使用者看到的是「按了登出完全沒反應」。
  static Future<void> _logOut(BuildContext context) async {
    final confirm = await showAppDialog(
      context,
      title: '要登出嗎？',
      message: '你的進度存在雲端，下次用同一個帳號登入就會回來。',
      confirmLabel: '登出',
      cancelLabel: '取消',
    );
    if (confirm != true || !context.mounted) return;

    // 先取出來，之後的 await 會讓這個 context 不再保證可用。
    final navigator = Navigator.of(context);
    final state = AppScope.of(context);

    await state.saveNow();
    await AuthService().signOut();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final delDays = s.deletionDaysLeft;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          '設定',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          const SectionLabel('訓練問卷', trailing: '更新後立即重新推薦'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: const [
                _Row(label: '每週健身天數', value: '4 天'),
                _Row(label: '每次健身時長', value: '60–90 分'),
                _Row(label: '健身目標', value: '增肌'),
                _Row(label: '健身經驗', value: '中階'),
              ],
            ),
          ),
          const SectionLabel('個人資料'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                _Row(label: '身高', value: s.heightText(s.heightCm)),
                _Row(label: '體重', value: s.weightText(s.bodyweightKg)),
                const _Row(
                  label: '生日',
                  value: '1996 / 03 / 12',
                  readOnly: true,
                ),
                _Row(label: '性別', value: s.isMale ? '男' : '女', readOnly: true),
                // 選填。填了才收得到出貨、處罰與申訴結果、帳號刪除排程
                // 三類電子郵件通知；不填一樣由推播與 App 內通知承擔。
                _Row(
                  label: '電子郵件',
                  value: s.email ?? '未填寫（選填）',
                  onTap: () => _editEmail(context, s),
                ),
              ],
            ),
          ),
          const SectionLabel('顯示偏好'),
          Panel(
            child: _Toggle(
              label: '使用公制單位',
              sub: s.metricUnits ? '公斤 / 公分' : '磅 / 英吋',
              value: s.metricUnits,
              onChanged: (v) => s.setFlag(metric: v),
            ),
          ),
          // 這一段講的是「你的進度存在哪裡」。接了帳號之後答案變了 ——
          // 還寫「存在這台裝置上」的話，使用者換裝置前會先把進度抄下來。
          SectionLabel('儲存', trailing: s.demo ? '存在這台裝置上' : '存在你的帳號'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.demo
                      ? '進度會自動存到本機，關掉重開仍在。已存 ${s.saveCount} 次。'
                      : '進度會自動存到你的帳號。換裝置、清瀏覽器資料都不會不見。'
                          '已存 ${s.saveCount} 次。',
                  style: T.body(),
                ),
                // 說清楚哪些東西沒存 —— 使用者發現團隊變回去時，
                // 要能在這裡找到答案，而不是以為壞掉了。
                // 接了帳號就沒有這回事，那句話也就不必說。
                if (s.demo) ...[
                  const SizedBox(height: 6),
                  Text(
                    '不含動作庫、貼文、訂單、團隊與後台佇列。',
                    style: T.caption(),
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    label: '重設示範資料',
                    kind: BtnKind.secondary,
                    onPressed: () async {
                      final ok = await showAppDialog(
                        context,
                        title: '清除存檔？',
                        message: '這台裝置上的進度會全部刪除，'
                            '下次開啟回到最初的示範資料。這個動作無法復原。',
                        confirmLabel: '清除',
                        destructive: true,
                      );
                      if (ok != true || !context.mounted) return;
                      await s.clearSaved();
                      if (!context.mounted) return;
                      showToast(context, '已清除，重開 App 即回到初始狀態');
                    },
                  ),
                ],
              ],
            ),
          ),
          // 模擬載入與模擬離線是除錯用的控制項，跟 `[QA-02n]`／`[QA-02o]`
          // 那一批同一個道理 —— 一般使用者看到只會問「這是什麼」。
          if (s.developerMode) ...[
            const SectionLabel('示範', trailing: '開發者模式'),
            Panel(
              child: Column(
                children: [
                  _Toggle(
                    label: '模擬首次載入',
                    sub: s.demoLoadMs > 0
                        ? '每頁首次進入先顯示 ${s.demoLoadMs} 毫秒骨架屏'
                        : '關閉。資料就在記憶體裡，平白讓每頁慢一秒只是折磨人',
                    value: s.demoLoadMs > 0,
                    onChanged: (v) => s.setDemoLoadMs(v ? 900 : 0),
                  ),
                  const SizedBox(height: 14),
                  _Toggle(
                    label: '模擬離線',
                    sub: '載入結束時改走錯誤頁，可按重新載入重試'
                        '${s.demoLoadMs > 0 ? '' : '（需先開啟模擬首次載入）'}',
                    value: s.demoOffline,
                    onChanged: (v) => s.setDemoOffline(v),
                  ),
                ],
              ),
            ),
            // 登入後每一塊同步的結果。這幾塊全部吞掉錯誤 —— 那是對的
            // （社群讀不到不該擋住訓練），代價是出問題時完全沒有跡象。
            // 「申請送得出去、對方看不到」查了三輪都在猜，就是因為
            // 這幾條路徑什麼都不說。
            const SectionLabel('登入同步', trailing: '開發者模式'),
            if (s.chatSendError != null) ...[
              Panel(
                color: C.statusError.withValues(alpha: 0.08),
                border: C.statusError,
                child: Text('最近一次私訊送出失敗：\n${s.chatSendError}',
                    style: const TextStyle(
                        fontSize: 11.5, color: C.statusError)),
              ),
              const SizedBox(height: 10),
            ],
            Panel(
              child: s.syncReport.isEmpty
                  ? const Text(
                      '尚未同步。這一份在登入後才會有內容 ——'
                      '目前是未登入，或還沒跑完。',
                      style: TextStyle(
                          color: AppColors.textFaint, fontSize: 11.5),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in s.syncReport.entries) ...[
                          Text(
                            e.key,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.value,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: e.value.startsWith('失敗') ||
                                      e.value.contains('⚠️')
                                  ? C.statusError
                                  : AppColors.textFaint,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
          ],
          const SectionLabel('訓練設定'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '持有器材明細',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  '動作庫的器材篩選預設帶入此處',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _equipment)
                      GestureDetector(
                        onTap: () => s.toggleEquipment(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: s.ownedEquipment.contains(e)
                                ? AppColors.accent
                                : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            e,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: s.ownedEquipment.contains(e)
                                  ? AppColors.onAccent
                                  : AppColors.textDim,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 26, color: AppColors.line),
                _Toggle(
                  label: 'AI 自動優化',
                  sub: '每 3 次訓練後自動調整長期課表範本',
                  value: s.aiAutoOptimize,
                  onChanged: (v) => s.setFlag(autoOptimize: v),
                ),
                const Divider(height: 26, color: AppColors.line),
                // 其後仍可於設定頁補填，補填時同樣產生「使用者已選擇偏好訓練時段」。
                _Row(
                  label: '偏好訓練時段',
                  value: s.preferredTimes.isEmpty
                      ? '未填'
                      : '${s.preferredTimes.filledDays} 天',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PreferredTimesScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionLabel('隱私', trailing: '兩者各自獨立'),
          Panel(
            child: Column(
              children: [
                _Toggle(
                  label: '六維能力值對外可見',
                  sub: '關閉後他人檢視你的個人檔案時不呈現能力值區塊',
                  value: s.abilityPublic,
                  onChanged: (v) => s.setFlag(ability: v),
                ),
                const Divider(height: 26, color: AppColors.line),
                _Toggle(
                  label: '綜合能力等級對外可見',
                  sub: '關閉六維但保留綜合，即只露出整體評價、隱藏各部位細節',
                  value: s.overallGradePublic,
                  onChanged: (v) => s.setFlag(overall: v),
                ),
                if (s.isInstructor) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '你具備教官身分，上述設定不生效 —— 教官的六維能力值強制呈現。',
                      style: TextStyle(
                        color: AppColors.bronze,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel('帳號'),
          // 沒有初始化 Firebase 就不顯示登出 —— 既有的 widget 測試
          // （畫面爬蟲會走過每一頁）沒有 Firebase，碰 FirebaseAuth.instance
          // 會當場丟例外。用 Firebase.apps 判斷是安全的：它是純查詢，不會拋。
          if (Firebase.apps.isNotEmpty) ...[
            Panel(
              child: InkWell(
                onTap: () => _logOut(context),
                child: const Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.textFaint),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text('登出', style: TextStyle(fontSize: 13.5)),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Panel(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountDeleteScreen()),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.bronze,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      delDays == null ? '申請刪除帳號' : '帳號待刪除　·　冷靜期剩餘 $delDays 天',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.bronze,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.textFaint,
                  ),
                ],
              ),
            ),
          ),
          if (s.isMember) ...[
            const SizedBox(height: 8),
            Panel(
              child: InkWell(
                onTap: () => showToast(context, '導向 Apple 原生訂閱管理面板'),
                child: const Row(
                  children: [
                    Icon(
                      Icons.card_membership,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text('訂閱管理', style: TextStyle(fontSize: 13.5)),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 使用者已填入電子郵件。空白即清空。
Future<void> _editEmail(BuildContext context, AppState s) async {
  final ctrl = TextEditingController(text: s.email ?? '');
  final ok = await showAppSheet<bool>(
    context,
    title: '電子郵件（選填）',
    child: StatefulBuilder(
      builder: (context, setSheetState) {
        final error = AppState.isValidEmail(ctrl.text)
            ? null
            : '電子郵件格式不正確。';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '填了才收得到出貨、處罰與申訴結果、帳號刪除排程三類信件。'
              '不填一樣會收到推播與 App 內通知，不會少掉任何權益。',
              style: T.caption(),
            ),
            const SizedBox(height: S.md),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              style: T.body(),
              onChanged: (_) => setSheetState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'name@example.com',
                hintStyle: T.body(color: C.textDisabled),
                errorText: error,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: S.base, vertical: S.md),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.control),
                ),
              ),
            ),
            const SizedBox(height: S.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: ctrl.text.trim().isEmpty ? '清空並關閉' : '儲存',
                onPressed: error == null
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;
  final err = s.setEmail(ctrl.text);
  showToast(context, err ?? (s.email == null ? '已清空電子郵件' : '已更新電子郵件'));
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool readOnly;
  final VoidCallback? onTap;
  const _Row({
    required this.label,
    required this.value,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: readOnly ? AppColors.textFaint : AppColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            readOnly ? Icons.lock_outline : Icons.chevron_right,
            size: 15,
            color: AppColors.textFaint,
          ),
        ],
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      AppSwitch(value: value, onChanged: onChanged),
    ],
  );
}
