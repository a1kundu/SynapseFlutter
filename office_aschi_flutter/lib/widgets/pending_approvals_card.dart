import 'package:flutter/material.dart';
import '../models/models.dart';
import 'section_card.dart';

/// Reusable pending approvals card showing members awaiting approval.
class PendingApprovalsCard extends StatelessWidget {
  final List<ReporteeResponse> pendingMembers;
  final ValueChanged<int> onApprove;
  final ValueChanged<ReporteeResponse> onDeny;

  const PendingApprovalsCard({
    super.key,
    required this.pendingMembers,
    required this.onApprove,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SectionCard(
      title: 'Pending Approvals',
      contentPadding: EdgeInsets.zero,
      children: [
        ...pendingMembers.map(
          (r) => ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.secondary,
              child: Text(
                r.friendlyName[0].toUpperCase(),
                style: TextStyle(color: cs.onSecondary),
              ),
            ),
            title: Text(r.friendlyName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => onApprove(r.id),
                  child: const Text('Approve'),
                ),
                TextButton(
                  onPressed: () => onDeny(r),
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  child: const Text('Deny'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
