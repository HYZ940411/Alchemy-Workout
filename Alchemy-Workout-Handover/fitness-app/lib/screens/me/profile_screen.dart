import 'package:flutter/material.dart';

import '../../domain/rank.dart';
import '../../design/skeleton.dart';
import '../../state/app_state.dart';
import '../../widgets/load_boundary.dart';
import '../social/follow_list_screen.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/radar_chart.dart';
import '../social/chat_screen.dart';
import '../social/post_card.dart';
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
///
/// **這一頁整頁的資料都要跟著 [ProfileScreen.viewing] 走。**
/// 入口補好之後（`[QA-02i]`）畫面終於點得進去，才看得出裡面的欄位
/// 幾乎全部讀的是 `s.` —— 我自己的階級、我自己的粉絲數、我自己的
/// 六維點數、動態牆上的前兩則貼文。於是每個人的檔案頁長得一模一樣，
/// 而且顯示的是看的人自己。與 `[QA-02f]`／`[QA-02i]` 同一種病：
/// 每一塊各自是對的，接縫是斷的。
/// [uid] 是呼叫端手上那個人的雲端身分，**拿得到就一定要傳**。
///
/// 暱稱可以改 —— 只給名字的話，對方改名之後這一頁的階級與六維會一起
/// 掉回預設值。貼文、私訊、名冊上本來就帶著 uid。
void openProfile(BuildContext context, String name, {String? uid}) {
  final self = AppScope.of(context).displayName;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        ProfileScreen(viewing: name == self ? null : name, viewingUid: uid),
  ));
}

class ProfileScreen extends StatefulWidget {
  final String? viewing; // null 表示看自己

  /// 被看的人的雲端身分。空值時退回用暱稱反查（見 [openProfile]）。
  final String? viewingUid;
  const ProfileScreen({super.key, this.viewing, this.viewingUid});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? get viewing => widget.viewing;
  String? get viewingUid => widget.viewingUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // **去數一次他現在有幾個粉絲。**
    //
    // 公開檔案上那個數字只有他本人寫得了，所以我關注他不會讓它變動 ——
    // 直接顯示那個值，等於顯示「他上次登入時的粉絲數」。
    // 不 await：數回來會 notifyListeners，畫面自己重畫。
    final s = AppScope.of(context);
    final name = viewing;
    if (name != null) {
      s.ensureFollowerCount(name, viewingUid ?? s.uidOf(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final isSelf = viewing == null;
    final frozen = viewing ?? s.displayName;
    // **可見度不是由我這邊的開關決定的。** 原本寫 `s.abilityPublic`，
    // 那是「我要不要公開我的」，拿來決定「我看不看得到他的」是反的。
    // 對方公開了什麼，就由我們手上有沒有他那份資料如實反映。
    // 拿得到 uid 就用 uid 查 —— 暱稱可以改，uid 不會。
    final uid = isSelf ? s.myUid : (viewingUid ?? s.uidOf(frozen));
    // 這個人**現在**的名字。呼叫端手上那份是他當時叫什麼 ——
    // 從三個月前的貼文點進來的話，那個名字早就過期了。
    final name = isSelf ? s.displayName : s.nameOf(frozen, uid: uid);
    final ability = s.abilityOf(name, uid: uid);
    final grade = s.gradeOf(name, uid: uid);
    final reputation = s.reputationOf(name, uid: uid);
    final isInstructor =
        isSelf ? s.isInstructor : s.instructors.any((i) => i.name == name);
    // 帶上 uid —— 與上面那幾個 `abilityOf`／`gradeOf` 同一個理由。
    final myPosts = s.postsBy(name, uid: uid);

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
                    if (isInstructor) ...[
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
                        value: '${s.rankOf(name, uid: uid)}',
                        unit: '/ 99',
                      ),
                    ),
                    Expanded(
                      // 粉絲數為儲存欄位，點進去看的是關注關係本身。
                      // **只有自己那一頁點得進去** —— 那份清單是我的關注
                      // 與我的粉絲，掛在別人的粉絲數上會開出不相干的東西。
                      child: GestureDetector(
                        onTap: isSelf
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const FollowListScreen(initialTab: 1),
                                  ),
                                )
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: StatTile(
                          label: '粉絲數',
                          value: '${s.followersOf(name, uid: uid)}',
                        ),
                      ),
                    ),
                    if (reputation != null)
                      Expanded(
                        child: StatTile(
                          label: '聲望點數',
                          value: '$reputation',
                          valueColor: C.accentDeep,
                        ),
                      ),
                  ],
                ),
                // 階級進度要有對方的累積經驗值才畫得出來，而公開檔案
                // 不含那個欄位 —— 畫一條看自己的進度掛在別人名下是錯的。
                if (isSelf) ...[
                  const SizedBox(height: 12),
                  ProgressBar(value: rankProgressOf(s.totalExp).ratio),
                ],
              ],
            ),
          ),
          if (!isSelf) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: s.isFollowing(name, uid: uid) ? '已關注' : '關注',
                    onPressed: () {
                      if (socialLocked(context, '關注')) return;
                      s.toggleFollow(name, uid: uid);
                    },
                    // 已關注＝取消關注，屬破壞性動作，用次要樣式（§4.5）
                    kind: s.isFollowing(name, uid: uid)
                        ? BtnKind.secondary
                        : BtnKind.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: '開始聊天',
                    kind: BtnKind.secondary,
                    // 私訊**不受新手任務閘門約束** —— 規格鎖的是發文、
                    // 按讚、留言、分享、關注五項。封鎖過的人不給聊；
                    // 停權者的攔截在對話頁送出那一步，讀得到不代表送得出。
                    onPressed: s.isBlocked(name)
                        ? null
                        : () {
                            // **先建好再 push。** 寫在 `builder:` 裡的話
                            // `conversationWith` 的 `notifyListeners()` 會在
                            // build 期間觸發，Flutter 當場拋例外 ——
                            // 也就是「第一次找某人聊天」必定閃退。
                            final c = s.conversationWith(name);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(conversation: c),
                            ));
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
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
                          : () async {
                              s.applyMentor(ins!);
                              final r = await s.lastWrite('拜師申請');
                              if (!context.mounted) return;
                              showToast(
                                  context,
                                  r.ok
                                      ? '已送出申請，7 天內未回應即逾期'
                                      : '申請沒有送達：${r.why}');
                            },
                      kind: BtnKind.secondary,
                    );
                  }),
                ),
              ],
            ),
          ],
          // **自己的檔案照常顯示，但要標出哪些別人看不到。**
          //
          // 2026-09-28 使用者裁決 A。在此之前兩個畫面做法不一樣：
          // 「我的」分頁把「綜合 X」整顆藏起來（註解寫「免得誤以為別人
          // 看得到」），而這一頁完整顯示卻**沒有任何標示** ——
          // 同一件事兩種處理，而且都不對。
          //
          // 藏起來是錯的方向：那是我自己的檔案，我當然該看得到我自己的
          // 能力值。**用「資訊消失」來表達「未公開」，使用者只會以為壞了**
          // —— 使用者找不到那顆標籤就是這樣（他問「我要去哪裡找更多」）。
          SectionLabel('能力值',
              trailing: isSelf && !(s.abilityPublic && s.overallGradePublic)
                  ? '部分未公開'
                  : null),
          if (isSelf && !s.abilityPublic) ...[
            Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.visibility_off_outlined,
                      size: Sz.iconDense, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.overallGradePublic
                          ? '六維能力值只有你看得到，別人只看得到綜合能力等級。'
                          : '能力值只有你看得到，別人檢視你的檔案時不呈現這一區。',
                      style: T.caption(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ] else if (isSelf && !s.overallGradePublic) ...[
            Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.visibility_off_outlined,
                      size: Sz.iconDense, color: AppColors.textDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('綜合能力等級只有你看得到。', style: T.caption()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (ability != null)
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
                    Center(child: RadarChart(points: ability)),
                    const SizedBox(height: 6),
                    if (grade != null)
                      Text(
                        '綜合能力等級　$grade',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
            )
          else if (grade != null)
            Panel(
              child: Column(
                children: [
                  Text(
                    grade,
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
          // 原本取的是 `s.visiblePosts` —— 那是整個動態牆，
          // 於是別人的檔案頁列的是不相干的人寫的東西。
          SectionLabel('公開貼文',
              trailing: myPosts.isEmpty ? null : '${myPosts.length} 篇'),
          if (myPosts.isEmpty)
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                isSelf ? '你還沒有發過貼文。' : '$name 沒有公開的貼文。',
                style: const TextStyle(
                    color: AppColors.textDim, fontSize: 12.5),
              ),
            ),
          // **與動態牆同一張卡**（`PostCard`）。
          //
          // 在此之前這裡是自己畫的兩行純文字、`take(2)`、沒有按讚留言
          // 檢舉，也點不進貼文詳情 —— 使用者回報「公開貼文顯示不完整，
          // 少了更早發布的文章」。
          //
          // 不補按鈕、改抽出來共用：補的話就是第二張會慢慢長歪的卡片，
          // 而這個專案的 bug 有一整排正是「同一個決定寫在兩個地方，
          // 只有一處做對」。
          //
          // 也不再截斷。截斷本身沒有壞處，壞的是**截斷而不說** ——
          // 使用者以為那就是全部。要截就得有「看更多」，而這一頁
          // 本來就會捲動，那顆按鈕只是多一次點擊。
          for (final p in myPosts) PostCard(post: p),
        ],
      ),
    );
  }
}
