import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/components.dart';
import '../design/typography.dart';
import '../state/app_state.dart';
import '../widgets/tab_bar.dart';
import 'home_screen.dart';
import 'social/notifications_screen.dart';
import 'me/more_screen.dart';
import 'plan_select_screen.dart';
import 'workout_screen.dart';
import 'shop/shop_hub_screen.dart';
import 'social/social_shell.dart';

/// 五格資訊架構（§7）：首頁／社群／訓練／商店／我的
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  AppState? _state;

  /// 重新整理網頁前正在練的那一場：讀回存檔後自動跳回訓練頁。
  ///
  /// 進場時存檔可能還沒讀完（沒接帳號的路徑是非同步讀），所以除了進場檢查一次，
  /// 還要聽狀態變化 —— 存檔一套用完，下一次通知就會帶使用者回去。
  void _resumeWorkout() {
    final s = _state;
    if (s == null || !mounted || !s.takeWorkoutResume()) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WorkoutScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _state = AppScope.of(context)..addListener(_resumeWorkout);
      _resumeWorkout();
    });
  }

  @override
  void dispose() {
    _state?.removeListener(_resumeWorkout);
    super.dispose();
  }

  static const _titles = ['首頁', '社群', '訓練', '商店', '我的'];

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.bgPage,
        appBar: AppBar(
          // §8.3 標題置中；右側無功能鍵時仍保留空位，故用 centerTitle
          title: Text(_titles[index], style: T.h3()),
          actions: [
            // 通知原本只在「我的 → 社群」底下。它是全 App 的收件匣，
            // 未讀數不掛在看得到的地方就等於沒有。
            Builder(builder: (context) {
              final s = AppScope.of(context);
              return IconButton(
                tooltip: '通知',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen()),
                ),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded,
                        size: Sz.iconDefault),
                    if (s.unreadNotifications > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: CountBadge(s.unreadNotifications),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: index,
            children: const [
              HomeScreen(),
              SocialShell(),
              PlanSelectScreen(),
              ShopHubScreen(),
              MoreScreen(),
            ],
          ),
        ),
        bottomNavigationBar: AppTabBarBottom(
          index: index,
          onTap: (i) => setState(() => index = i),
        ),
      );
}
