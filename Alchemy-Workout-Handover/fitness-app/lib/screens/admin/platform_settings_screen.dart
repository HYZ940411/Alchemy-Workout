import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../domain/admin.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'admin_accounts_screen.dart';
import 'platform_catalog_screen.dart';
import 'platform_definitions_screen.dart';
import '../../domain/task_pool.dart';
import 'exam_bank_screen.dart';
import 'setting_group_screen.dart';

/// Read Model：平台設定（16 個管理員 Command 的入口）
///
/// 分三區，依「改動後會改變使用者拿到什麼」的近遠排列：
/// 使用者直接拿到的內容、判定門檻與參數、管理員帳號本身。
class PlatformSettingsScreen extends StatelessWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    void go(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    final allowed = s.canConfigure;
    final log = s.settingLog;

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('平台設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          S.base,
          S.base,
          S.base,
          S.scrollBottom,
        ),
        children: [
          if (!allowed)
            AppCard(
              borderColor: C.statusError,
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: Sz.iconDense, color: C.statusError),
                  const SizedBox(width: S.md),
                  Expanded(
                    child: Text(
                      s.admin.status == AdminStatus.disabled
                          ? '帳號已停用，不得執行任何管理員 Command —— 本頁全為唯讀。'
                          : '權限組未涵蓋「平台設定」，本頁全為唯讀。',
                      style: T.caption(color: C.statusError),
                    ),
                  ),
                ],
              ),
            )
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('16 個 Command，權限組皆為平台設定',
                      style: T.body(weight: FontWeight.w600)),
                  const SizedBox(height: S.sm),
                  Text(
                    '每一次變更都記入下方的變更紀錄，攜帶所變更的項目、變更前的值、'
                    '變更後的值。全部 Command 的 Postcondition 一律不追溯既有紀錄。',
                    style: T.caption(),
                  ),
                ],
              ),
            ),

          // 左欄：改動後直接改變使用者拿到什麼
          const SectionTitle('使用者拿到的內容', trailing: '4 個'),
          ListGroup(
            rows: [
              ListRow(
                title: '設定訓練計畫',
                subtitle: '所需階級、是否開放金幣購買　·　${s.platformPlans.length} 份',
                chevron: true,
                onTap: () => go(const PlatformPlansScreen()),
              ),
              ListRow(
                title: '設定平台動作',
                subtitle:
                    '相對強度係數、預設組間休息　·　${s.platformExercises.length} 筆',
                chevron: true,
                onTap: () => go(const PlatformExercisesScreen()),
              ),
              ListRow(
                title: '設定成就定義',
                subtitle: '達成門檻與獎勵　·　${s.achievements.length} 項',
                chevron: true,
                onTap: () => go(const AchievementDefsScreen()),
              ),
              ListRow(
                title: '設定獎勵定義',
                subtitle: '訓練與簽到的金幣、經驗值',
                chevron: true,
                showDivider: false,
                onTap: () => go(const SettingGroupScreen(groupId: 'reward')),
              ),
            ],
          ),

          const SectionTitle('任務與課表範本', trailing: '3 個'),
          ListGroup(
            rows: [
              ListRow(
                title: '設定新手任務範本',
                subtitle: '三選一的三個選項',
                chevron: true,
                onTap: () => go(const NoviceTemplateScreen()),
              ),
              ListRow(
                title: '設定每日任務池',
                subtitle: '池內 ${s.taskPool.length} 項　·　每日抽 $kDailyDrawCount 項',
                chevron: true,
                onTap: () => go(const DailyTaskPoolScreen()),
              ),
              ListRow(
                title: '設定限時任務',
                subtitle: '全平台統一，一個指派日一組　·　'
                    '團隊項目 ${teamItems(s.taskPool).length} 項',
                chevron: true,
                showDivider: false,
                onTap: () => go(const TimedTaskConfigScreen()),
              ),
            ],
          ),

          const SectionTitle('門檻與參數', trailing: '6 個'),
          ListGroup(
            rows: [
              ListRow(
                title: '設定能力值參數',
                subtitle: '六階門檻、基準值與映射係數　·　即時生效',
                chevron: true,
                onTap: () => go(const SettingGroupScreen(groupId: 'ability')),
              ),
              ListRow(
                title: '設定階級門檻',
                subtitle: '滿階經驗值與曲線指數',
                chevron: true,
                onTap: () => go(const SettingGroupScreen(groupId: 'rank')),
              ),
              ListRow(
                title: '設定教官初審門檻',
                subtitle: '需求階級、需求次數、品質分折抵與一票否決',
                chevron: true,
                onTap: () =>
                    go(const SettingGroupScreen(groupId: 'instructorGate')),
              ),
              ListRow(
                title: '設定教官測驗　·　參數',
                subtitle: '題數與雙門檻的及格標準',
                chevron: true,
                onTap: () => go(const SettingGroupScreen(groupId: 'exam')),
              ),
              ListRow(
                title: '設定教官測驗　·　題庫',
                subtitle: '選擇題 ${s.examBank.where((q) => q.type == ExamQuestionType.multipleChoice).length} 題'
                    '　·　簡答題 ${s.examBank.where((q) => q.type == ExamQuestionType.shortAnswer).length} 題',
                chevron: true,
                onTap: () => go(const ExamBankScreen()),
              ),
              ListRow(
                title: '設定補簽回補範圍',
                subtitle: '目前 ${s.makeupRangeDays} 天',
                chevron: true,
                onTap: () => go(const SettingGroupScreen(groupId: 'makeup')),
              ),
              ListRow(
                title: '設定會員權益',
                subtitle: '訂閱價格與每月 AI 點數配額',
                chevron: true,
                showDivider: false,
                onTap: () =>
                    go(const SettingGroupScreen(groupId: 'membership')),
              ),
            ],
          ),

          const SectionTitle('管理員帳號', trailing: '3 個'),
          ListGroup(
            rows: [
              ListRow(
                title: '新增／停用管理員、調整權限組',
                subtitle: '${s.admins.where((a) => a.status == AdminStatus.active).length} 位生效中'
                    '，共 ${s.admins.length} 位',
                chevron: true,
                showDivider: false,
                onTap: () => go(const AdminAccountsScreen()),
              ),
            ],
          ),

          SectionTitle('變更紀錄', trailing: '${log.length} 筆'),
          if (log.isEmpty)
            AppCard(
              child: Text(
                '尚無變更。既已承諾調整不追溯既有紀錄，就須有可稽核的依據記錄'
                '何時改的、改成什麼 —— 每一次設定變更都會出現在這裡。',
                style: T.caption(),
              ),
            )
          else
            ListGroup(
              rows: [
                for (var i = 0; i < log.length; i++)
                  ListRow(
                    title: '${log[i].event}　·　${log[i].item}',
                    subtitle: '${log[i].before} → ${log[i].after}　·　'
                        '${_stamp(log[i].at)}　·　${log[i].by}',
                    showDivider: i != log.length - 1,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _stamp(DateTime t) =>
      '${t.month}/${t.day} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
