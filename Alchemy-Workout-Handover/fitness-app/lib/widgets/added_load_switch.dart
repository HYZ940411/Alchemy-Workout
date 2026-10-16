import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// 徒手動作的「外加負重」開關。
///
/// 徒手動作（伏地挺身、引體向上）的重量欄記的是**外加負重**，預設 0、鎖著不給調；
/// 要記負重引體向上之類才打開。關掉時重量回到 0。
class AddedLoadSwitch extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const AddedLoadSwitch({super.key, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sz.tapTarget),
        child: Row(
          children: [
            Expanded(
              child: Text('外加負重（例如負重引體向上）', style: T.caption()),
            ),
            Switch(value: on, onChanged: onChanged),
          ],
        ),
      );
}
