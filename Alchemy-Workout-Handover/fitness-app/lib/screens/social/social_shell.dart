import 'package:flutter/material.dart';

import '../../theme.dart';
import 'chat_screen.dart';
import 'feed_screen.dart';
import 'mentor_screen.dart';
import 'team_screen.dart';

/// 社群分頁：動態牆 / 團隊 / 師徒 / 私訊
class SocialShell extends StatelessWidget {
  const SocialShell({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textDim,
              dividerColor: AppColors.line,
              labelStyle:
                  TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: '動態'),
                Tab(text: '團隊'),
                Tab(text: '師徒'),
                Tab(text: '私訊'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  FeedScreen(),
                  TeamScreen(),
                  MentorScreen(),
                  ConversationsScreen(),
                ],
              ),
            ),
          ],
        ),
      );
}
