import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../me/profile_screen.dart';

/// 找人 —— 私訊的入口缺口。
///
/// ## 為什麼需要這一頁
///
/// 在此之前，要進到別人的公開檔案（也就是「開始聊天」那顆按鈕所在之處）
/// 只有兩條路：**在動態牆上點貼文作者**，或**在自己的關注／粉絲清單裡點**。
/// 於是「私訊一個還沒關注、也還沒發過文的人」在 App 裡做不到 ——
/// 不是規格這樣訂的，是沒有入口。
///
/// 規格反過來明講了這件事會發生：訊息分類有「陌生訊息」這一類，
/// 判定依據是**雙方非互相關注、非師徒、非同隊**。既然陌生人傳訊是
/// 預期內的情境，就必須有辦法找到陌生人。
///
/// 資料早就在手上了 —— `AuthGate` 登入時讀了 50 筆公開檔案，
/// `applyPublicProfiles()` 也把它們併進了 `socialUsers`。
/// 缺的只是一個看得到它們的地方。這是同一種病的第十二次：
/// 零件做好了，接縫沒接。
class FindPeopleScreen extends StatefulWidget {
  const FindPeopleScreen({super.key});

  @override
  State<FindPeopleScreen> createState() => _FindPeopleScreenState();
}

class _FindPeopleScreenState extends State<FindPeopleScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);

    // 自己不列（沒有「私訊自己」這回事），封鎖過的也不列
    // —— 檔案頁上那顆「開始聊天」對封鎖過的人本來就是暗的。
    final people = [
      for (final u in s.socialUsers)
        if (u.name != s.displayName && !s.isBlocked(u.name))
          if (_q.isEmpty || u.name.toLowerCase().contains(_q)) u,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      backgroundColor: C.bgPage,
      appBar: AppBar(title: const Text('找人')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.base, S.base, S.base, 0),
            child: TextField(
              controller: _ctrl,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: '輸入暱稱搜尋',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          Expanded(
            child: people.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title: _q.isEmpty ? '還沒有其他人' : '找不到「${_ctrl.text.trim()}」',
                    message: _q.isEmpty
                        ? '這裡列的是平台上的其他使用者。目前一個都讀不到 ——'
                            '可能是還沒有人註冊，或是登入時沒讀到公開檔案。'
                        : '換個關鍵字試試。這裡只找得到已經載入的使用者。',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        S.base, S.base, S.base, S.scrollBottom),
                    children: [
                      ListGroup(rows: [
                        for (var i = 0; i < people.length; i++)
                          ListRow(
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: C.bgPage,
                              child: Text(
                                people[i].name.characters.first,
                                style: T.body(weight: FontWeight.w700),
                              ),
                            ),
                            title: people[i].name,
                            subtitle: '階級 ${people[i].rank}　·　'
                                '綜合 ${people[i].grade}'
                                '${s.following.contains(people[i].name) ? '　·　追蹤中' : ''}',
                            chevron: true,
                            // 點進公開檔案，「開始聊天」在那裡。
                            onTap: () => openProfile(context, people[i].name),
                            showDivider: i != people.length - 1,
                          ),
                      ]),
                      const SizedBox(height: S.base),
                      Text(
                        '不必先關注也能傳訊息。對方會在「陌生訊息」收到；'
                        '互相關注、同隊或有師徒關係之後，才會歸到「一般訊息」。',
                        style: T.caption(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
