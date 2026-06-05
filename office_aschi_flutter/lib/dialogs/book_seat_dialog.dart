import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../utils/snackbar_service.dart';

/// Dialog for booking a seat. Shows person selector, date, and TOTP code input.
///
/// Returns `true` if booking was successful, `false` or `null` if cancelled.
Future<bool?> showBookSeatDialog(
  BuildContext context, {
  required int seatId,
  required String seatLabel,
  required DateTime selectedDate,
  required List<ReporteeResponse> availableReportees,
  required int? currentReporteeId,
  required ValueNotifier<String?> clipboardOtp,
  required void Function(TextEditingController ctrl, String code)
  pasteClipboardCode,
  required void Function(BuildContext ctx) launchAuthenticator,
}) async {
  if (availableReportees.isEmpty) {
    showRootSnackBar(
      const SnackBar(content: Text('No available members to book')),
    );
    return null;
  }

  final api = ApiService();
  final dateString = DateFormat('yyyy-MM-dd').format(selectedDate);

  ReporteeResponse? selected = currentReporteeId != null
      ? availableReportees.cast<ReporteeResponse?>().firstWhere(
              (r) => r!.id == currentReporteeId,
              orElse: () => null,
            ) ??
            availableReportees.first
      : availableReportees.first;
  final codeCtrl = TextEditingController();
  bool success = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text('Book $seatLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Date: ${DateFormat('EEE, MMM d').format(selectedDate)}'),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReporteeResponse>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Select Person'),
              items: availableReportees
                  .map(
                    (r) =>
                        DropdownMenuItem(value: r, child: Text(r.friendlyName)),
                  )
                  .toList(),
              onChanged: (v) => setDialogState(() => selected = v),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Enter the 6-digit TOTP code for '),
                  TextSpan(
                    text: selected?.friendlyName ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' to book seat.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AutofillGroup(
              child: TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'TOTP Code'),
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                enableSuggestions: false,
                autocorrect: false,
                maxLength: 6,
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: clipboardOtp,
              builder: (context, code, _) {
                if (code == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    onPressed: () => pasteClipboardCode(codeCtrl, code),
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: Text('Paste code: $code'),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            ElevatedButton.icon(
              onPressed: () => launchAuthenticator(ctx),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open Authenticator App'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (selected == null || codeCtrl.text.isEmpty) return;
              try {
                await api.bookSeat(
                  selected!.id,
                  seatId,
                  dateString,
                  codeCtrl.text,
                );
                success = true;
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  showRootSnackBar(
                    SnackBar(
                      content: Text(
                        'Booked ${selected!.friendlyName} on $seatLabel',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  showRootSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Book'),
          ),
        ],
      ),
    ),
  );

  return success;
}
