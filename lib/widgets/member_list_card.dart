import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/models.dart';
import 'section_card.dart';

/// Reusable members list card showing approved team members with remove action.
class MemberListCard extends StatelessWidget {
  final List<ReporteeResponse> members;
  final ValueChanged<ReporteeResponse> onRemove;

  const MemberListCard({
    super.key,
    required this.members,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SectionCard(
      title: 'Members',
      contentPadding: EdgeInsets.zero,
      children: [
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'No approved members yet.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          )
        else ...[
          ...members.asMap().entries.map((entry) {
            final i = entry.key;
            final r = entry.value;
            final color =
                AppColors.avatarColors[r.id % AppColors.avatarColors.length];
            return Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color,
                    child: Text(
                      r.friendlyName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(r.friendlyName),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove),
                    onPressed: () => onRemove(r),
                    tooltip: 'Remove member',
                  ),
                ),
                if (i < members.length - 1)
                  const Divider(height: 1, indent: 72),
              ],
            );
          }),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
