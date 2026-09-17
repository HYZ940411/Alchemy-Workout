import 'package:flutter/material.dart';

import '../../domain/ability.dart';
import '../../domain/rank.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import '../social/follow_list_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/radar_chart.dart';
import '../social/social_lock.dart';

/// Read Model：使用者個人檔案頁
/// 服務的 Actor 為「檢視他人檔案者」，故受對方的可見性設定約束。
/// 開啟某個人的公開檔案。
///
/// **這是「看別人」的唯一入口。** 在此之前 [ProfileScreen.viewing] 沒有
/// 任何呼叫端 —— 畫面做好了、關注按鈕也在，但沒有一條路通到它，
/// 於是社群裡看到的人點不進去，也就關注不了（`[QA-02i]`）。
///
/// 點到自己就開自己的那一頁（沒有「關注自己」這種東西）。
void openProfile(BuildContext context, String name) {
  final self = AppScope.of(context).displayName;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ProfileScreen(viewing: name == self ? null : name),
  ));
}

class ProfileScreen extends StatelessWidget {
  final String? viewing; // null 表示看自己
  const ProfileScreen({super.key, this.viewing});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isSelf = viewing == null;
    final name = viewing ?? s.displayName;
    // 他人檢視時受可見性設定約束；本人一律看得到。
    final showDims = isSelf || s.abilityPublic;
    final showOverall = isSelf || s.overallGradePublic;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          isSelf ? '我的檔案' : name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 50),
        children: [
          Panel(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.surfaceAlt,
                  child: Text(
                    name.characters.first,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (s.isInstructor && isSelf) ...[
                      const SizedBox(width: 8),
                      const Pill('教官'),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: '階級',
                        value: '${s.rank}',
                        unit: '/ 99',
                      ),
                    ),
                    Expanded(
                      // 粉絲數為儲存欄位，點進去看的是關注關係本身。
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const FollowListScreen(initialTab: 1),
                          ),
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: StatTile(
                          label: '粉絲數',
                          value: '${s.followerCount}',
                        ),
                      ),
                    ),
                    if (s.isInstructor)
                      Expanded(
                        child: StatTile(
                          label: '聲望點數',
                          value: '${s.instructorReputation}',
                          valueColor: C.accentDeep,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ProgressBar(value: rankProgressOf(s.totalExp).ratio),
              ],
            ),
          ),
          if (!isSelf) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: s.following.contains(name) ? '已關注' : '關注',
                    onPressed: () {
                      if (socialLocked(context, '關注')) return;
                      s.toggleFollow(name);
                    },
                    // 已關注＝取消關注，屬破壞性動作，用次要樣式（§4.5）
                    kind: s.following.contains(name)
                        ? BtnKind.secondary
                        : BtnKind.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Builder(builder: (context) {
                    // 拜師的對象只能是教官。這一頁看的是一般使用者，
                    // 是不是教官要查得出來，不能給一個按了沒事的按鈕。
                    final ins = s.instructors
                        .where((i) => i.name == name)
                        .firstOrNull;
                    final blocked = ins == null
                        ? '這位使用者不是教官。'
                        : s.mentorApplyBlockedReason(ins);
                    return AppButton(
                      label: ins == null ? '非教官' : '申請師徒關係',
                      onPressed: blocked != null
                          ? null
                          : () {
                              s.applyMentor(ins!);
                              showToast(context, '已送出申請，7 天內未回應即逾期');
                            },
                      kind: BtnKind.secondary,
                    );
                  }),
                ),
              ],
            ),
          ],
          const SectionLabel('能力值'),
          if (showDims)
            // F 圖表型骨架：六邊形實心 ＋ 數值列。
            // 新使用者六維有初始值，故本區塊沒有空狀態。
            LoadBoundary(
              id: 'radar',
              kind: SkeletonKind.chartF,
              rows: 4,
              padding: EdgeInsets.zero,
              builder: (context) => Panel(
                child: Column(
                  children: [
                    Center(child: RadarChart(points: s.points)),
                    const SizedBox(height: 6),
                    if (showOverall)
                      Text(
                        '綜合能力等級　${overallGrade(s.points)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
            )
          else if (showOverall)
            Panel(
              child: Column(
                children: [
                  Text(
                    overallGrade(s.points),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '對方僅公開綜合能力等級，各部位細節已隱藏',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            )
          else
            const Panel(
              child: Text(
                '對方未公開能力值。',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              ),
            ),
          const SectionLabel('公開貼文'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (final p in s.visiblePosts.take(2))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        p.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          color: AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
