import 'package:flutter/material.dart';

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
          const SectionLabel('儲存', trailing: '存在這台裝置上'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '進度會自動存到本機，關掉重開仍在。'
                  '已存 ${s.saveCount} 次。',
                  style: T.body(),
                ),
                const SizedBox(height: 6),
                // 說清楚哪些東西沒存 —— 使用者發現團隊變回去時，
                // 要能在這裡找到答案，而不是以為壞掉了。
                Text(
                  '不含平台目錄與社群假資料（動作庫、貼文、訂單、團隊、後台佇列）——'
                  '那些在真實系統裡來自伺服器，不是這台裝置上的東西。',
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
                          '下次開啟回到最初的假資料。這個動作無法復原。',
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
            ),
          ),
          const SectionLabel('示範', trailing: '本 App 沒有後端'),
          Panel(
            child: Column(
              children: [
                _Toggle(
                  label: '模擬首次載入',
                  sub: s.demoLoadMs > 0
                      ? '每頁首次進入先顯示 ${s.demoLoadMs} 毫秒骨架屏'
                      : '關閉。假資料就在記憶體裡，平白讓每頁慢一秒只是折磨人',
                  value: s.demoLoadMs > 0,
                  onChanged: (v) => s.setDemoLoadMs(v ? 900 : 0),
                ),
                const SizedBox(height: 14),
                _Toggle(
                  label: '模擬離線',
                  sub:
                      '載入結束時改走錯誤頁，可按重新載入重試'
                      '${s.demoLoadMs > 0 ? '' : '（需先開啟模擬首次載入）'}',
                  value: s.demoOffline,
                  onChanged: (v) => s.setDemoOffline(v),
                ),
              ],
            ),
          ),
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
