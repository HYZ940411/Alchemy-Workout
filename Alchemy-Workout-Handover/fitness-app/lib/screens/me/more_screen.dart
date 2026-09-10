import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../achievements_screen.dart';
import '../daily/mailbox_screen.dart';
import '../daily_screen.dart';
import '../radar_screen.dart';
import '../daily/makeup_screen.dart';
import '../leaderboard_screen.dart';
import '../shop/ai_credits_screen.dart';
import '../shop/membership_screen.dart';
import '../shop/orders_screen.dart';
import '../shop/coin_topup_screen.dart';
import '../shop/shop_screen.dart';
import '../admin/admin_home_screen.dart';
import '../ai/ai_adjust_screen.dart';
import '../signup/signup_screen.dart';
import '../social/blocked_list_screen.dart';
import '../social/inbox_screen.dart';
import '../social/follow_list_screen.dart';
import '../social/mentor_interaction_screen.dart';
import '../social/notifications_screen.dart';
import '../../domain/community.dart';
import '../train/custom_plans_screen.dart';
import '../train/exercise_library_screen.dart';
import '../design/counterpart_screen.dart';
import '../design/state_gallery_screen.dart';
import '../train/decay_screen.dart';
import '../train/tasks_screen.dart';
import '../train/training_history_screen.dart';
import 'instructor_apply_screen.dart';
import '../../domain/ability.dart';
import 'account_delete_screen.dart';
import 'profile_screen.dart';
import 'punishment_screen.dart';
import 'settings_screen.dart';

/// 其餘功能的入口彙整。
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 50),
      children: [
        _Header(state: s),
        const SectionLabel('能力值'),
        _Group(items: [
          _Item(Icons.radar_outlined, '六維能力值', '雷達圖、時間維度、耐力值',
              () => const _Wrap(title: '六維能力值', child: RadarScreen())),
          _Item(Icons.person_outline, '我的檔案', '可見性設定影響他人檢視',
              () => const ProfileScreen()),
        ]),
        const SectionLabel('訓練'),
        _Group(items: [
          _Item(Icons.history_rounded, '訓練歷史', '訓練清單與動作趨勢',
              () => const TrainingHistoryScreen()),
          _Item(Icons.tune_rounded, '自訂訓練', '名額、狀態機、審核進度',
              () => const CustomPlansScreen()),
          _Item(Icons.menu_book_rounded, '動作庫', '六肌群 ＋ 有氧 ＋ 我的動作',
              () => const ExerciseLibraryScreen()),
          _Item(Icons.flag_outlined, '新手 / 回歸任務', '三選一與退步回復',
              () => const TasksScreen()),
          _Item(Icons.trending_down_rounded, '能力值退步狀態', '六個各自獨立的計時器',
              () => const DecayScreen()),
        ]),
        const SectionLabel('每日'),
        _Group(items: [
          _Item(Icons.today_outlined, '每日簽到 / 每日任務', '兩份 Read Model',
              () => const _Wrap(title: '每日', child: DailyScreen())),
          _Item(Icons.restore_rounded, '補簽', '補簽券 ${s.makeupTickets} 張',
              () => const MakeupScreen()),
          _Item(Icons.markunread_mailbox_outlined, '獎勵信箱',
              '${s.unclaimedMail} 筆未領取', () => const MailboxScreen()),
          _Item(Icons.emoji_events_outlined, '成就', '9 類成就',
              () => const _Wrap(title: '成就', child: AchievementsScreen())),
          _Item(Icons.leaderboard_outlined, '個人排行榜', '階級分組',
              () => const _Wrap(title: '個人排行榜', child: LeaderboardScreen())),
        ]),
        const SectionLabel('商城與訂閱'),
        _Group(items: [
          _Item(Icons.storefront_outlined, '商城', '實體與虛擬商品',
              () => const ShopScreen()),
          _Item(Icons.receipt_long_outlined, '我的訂單',
              '${s.orders.length} 筆', () => const OrdersScreen()),
          _Item(Icons.savings_outlined, '金幣儲值', '4 檔面額',
              () => const CoinTopUpScreen()),
          _Item(Icons.auto_awesome_outlined, 'AI 點數',
              '月度 ${s.aiMonthly} ＋ 永久 ${s.aiPermanent}',
              () => const AiCreditsScreen()),
          _Item(Icons.workspace_premium_outlined, '會員訂閱',
              s.isMember ? '生效中' : 'NT\$190 / 月', () => const MembershipScreen()),
        ]),
        const SectionLabel('社群'),
        _Group(items: [
          _Item(Icons.notifications_none_rounded, '通知',
              s.unreadNotifications == 0
                  ? '推播與 App 內通知'
                  : '${s.unreadNotifications} 則未讀',
              () => const NotificationsScreen()),
          _Item(Icons.people_outline, '關注與粉絲',
              '關注 ${s.following.length}　·　粉絲 ${s.followerCount}',
              () => const FollowListScreen()),
          _Item(Icons.block_outlined, '封鎖名單',
              '${s.blockedUsers.length} 人', () => const BlockedListScreen()),
          _Item(
              Icons.mark_email_unread_outlined,
              '收件匣',
              s.inboxCount == 0
                  ? '團隊邀請、師徒申請'
                  : '${s.inboxCount} 筆等你回應',
              () => const InboxScreen()),
        ]),

        const SectionLabel('帳號'),
        _Group(items: [
          _Item(Icons.school_outlined, '教官申請', '階級 20 ＋ 訓練 50 次',
              () => const InstructorApplyScreen()),
          _Item(Icons.groups_2_outlined, '師徒互動頁', '教官方：學徒、提問、任務',
              () => const MentorInteractionScreen()),
          _Item(Icons.gavel_outlined, '處罰與申訴', '目前無處罰',
              () => const PunishmentScreen()),
          _Item(Icons.settings_outlined, '設定', '器材、隱私、帳號',
              () => const SettingsScreen()),
        ]),
        const SectionLabel('流程示範'),
        _Group(items: [
          _Item(Icons.app_registration, '註冊流程',
              '啟動、登入、手機驗證、條款、9 欄問卷、計畫推薦',
              () => const SignUpScreen()),
          _Item(Icons.auto_awesome_outlined, 'AI 自動優化', '會員權益，不扣點',
              () => const AiAdjustScreen(source: AiSource.autoOptimize)),
          _Item(Icons.admin_panel_settings_outlined, '管理員後台',
              '待審、訂單、商品、評分', () => const AdminHomeScreen()),
          _Item(Icons.grid_view_rounded, '骨架屏與錯誤頁', '六種骨架、四種空狀態、兩種錯誤頁',
              () => const StateGalleryScreen()),
          _Item(Icons.swap_horiz_rounded, '模擬對方',
              '需要第二個人的流程，在這裡把另一半走完',
              () => const CounterpartScreen()),
        ]),
      ],
    );
  }
}

/// 個人主頁的頁首（Figma 61）
///
/// 「我的」是一個著陸頁，不是設定清單的封面：先給人看自己是誰、練成什麼樣子，
/// 再往下才是各功能的入口。三個數字與兩張統計卡都是既有 Read Model 的投影，
/// 不新增任何欄位。
class _Header extends StatelessWidget {
  final AppState state;
  const _Header({required this.state});

  /// 累計訓練量（噸）。訓練歷史的容積和，非另存的欄位。
  double get _tons =>
      state.history.fold<double>(0, (a, h) => a + h.volume) / 1000;

  int get _myPosts =>
      state.posts.where((p) => p.author == state.displayName).length;

  @override
  Widget build(BuildContext context) {
    final del = state.deletionDaysLeft;
    return Column(
      children: [
        // 待刪除是「帳號停用」：登得進來，但只剩取消申請可用。
        // 這件事必須在著陸頁講，藏在設定裡等於沒講。
        if (del != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AccountDeleteScreen())),
              child: Panel(
                color: C.statusError.withValues(alpha: 0.08),
                border: C.statusError,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 18, color: C.statusError),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('帳號待刪除　·　冷靜期剩餘 $del 天',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: C.statusError)),
                    ),
                    const Text('取消申請',
                        style: TextStyle(fontSize: 12, color: C.statusError)),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Column(
            children: [
              // 底色不可用 surfaceAlt —— 它等於頁面底色，88px 的圓會整個消失，
              // 畫面上只剩一個浮著的字。前景交給 onFill 依實測對比決定。
              CircleAvatar(
                radius: Sz.avatarProfile / 2,
                backgroundColor: C.accentDeep,
                child: Text(state.displayName.characters.first,
                    style: TextStyle(
                        color: C.onFill(C.accentDeep),
                        fontWeight: FontWeight.w900,
                        fontSize: 34)),
              ),
              const SizedBox(height: 12),
              Text(state.displayName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Pill('階級 ${state.rank}', color: C.accentDeep),
                  const SizedBox(width: 8),
                  // 綜合能力等級可設為不公開；不公開時連自己的頁首也不掛，
                  // 免得誤以為別人看得到。
                  if (state.overallGradePublic)
                    Pill('綜合 ${overallGrade(state.points)}'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Count(value: '$_myPosts', label: '貼文'),
                  _Count(
                    value: '${state.followerCount}',
                    label: '粉絲',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FollowListScreen(initialTab: 1))),
                  ),
                  _Count(
                    value: '${state.following.length}',
                    label: '關注',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FollowListScreen())),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Panel(
                      child: StatTile(
                          label: '連續訓練',
                          value: '${state.trainingStreakDays}',
                          unit: '天'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Panel(
                      child: StatTile(
                          label: '累計訓練量',
                          value: _tons.toStringAsFixed(1),
                          unit: '噸'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _Count({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // 桌機的滑鼠停留會留下一塊灰底，三個數字裡只有一個亮著，
        // 看起來像被選取了。停留不給底，點下去才有回饋。
        hoverColor: Colors.transparent,
        highlightColor: C.press,
        splashColor: C.press,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textDim)),
            ],
          ),
        ),
      );
}

class _Item {
  final IconData icon;
  final String title;
  final String sub;
  final Widget Function() builder;
  const _Item(this.icon, this.title, this.sub, this.builder);
}

class _Group extends StatelessWidget {
  final List<_Item> items;
  const _Group({required this.items});

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            for (final it in items)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => it.builder()),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(it.icon, size: 17, color: AppColors.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(it.title,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(it.sub,
                                style: const TextStyle(
                                    color: AppColors.textFaint, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: AppColors.textFaint),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// 把原本嵌在分頁中的畫面包成獨立頁面。
class _Wrap extends StatelessWidget {
  final String title;
  final Widget child;
  const _Wrap({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          title: Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: child,
      );
}
