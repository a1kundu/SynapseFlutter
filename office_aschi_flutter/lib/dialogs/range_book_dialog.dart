import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../utils/snackbar_service.dart';

/// Result returned when the range book dialog is confirmed.
class RangeBookDialogResult {
  final ReporteeResponse? reportee;
  final int seatId;
  final String from;
  final String to;

  RangeBookDialogResult({
    this.reportee,
    required this.seatId,
    required this.from,
    required this.to,
  });
}

/// Dialog for booking a seat across a date range.
///
/// Shows member selector (if no current reportee identity), seat selector,
/// date range picker, TOTP code input, and day count info.
///
/// Returns a [RangeBookingResponse] if booking was successful, or `null` if
/// cancelled.
Future<RangeBookingResponse?> showRangeBookDialog(
  BuildContext context, {
  required List<SeatResponse> seats,
  required List<ReporteeResponse> availableReportees,
  required int? currentReporteeId,
  required DateTime defaultDate,
  required ValueNotifier<String?> clipboardOtp,
  required void Function(TextEditingController ctrl, String code)
  pasteClipboardCode,
  required void Function(BuildContext ctx) launchAuthenticator,
}) async {
  if (seats.isEmpty) {
    showRootSnackBar(
      const SnackBar(content: Text('No seats available to book')),
    );
    return null;
  }
  if (availableReportees.isEmpty) {
    showRootSnackBar(
      const SnackBar(content: Text('No available members to book')),
    );
    return null;
  }

  final api = ApiService();
  RangeBookingResponse? rangeResult;

  ReporteeResponse? selectedReportee = currentReporteeId != null
      ? availableReportees.cast<ReporteeResponse?>().firstWhere(
              (r) => r!.id == currentReporteeId,
              orElse: () => null,
            ) ??
            availableReportees.first
      : availableReportees.first;
  SeatResponse? selectedSeat = seats.first;
  DateTime fromDate = defaultDate;
  DateTime toDate = defaultDate.add(const Duration(days: 4));
  final codeCtrl = TextEditingController();

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final dayCount = toDate.difference(fromDate).inDays + 1;
        final isValid =
            selectedSeat != null &&
            selectedReportee != null &&
            dayCount > 0 &&
            dayCount <= 90;

        return AlertDialog(
          title: const Text('Book Date Range'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seat selector
                DropdownButtonFormField<SeatResponse>(
                  initialValue: selectedSeat,
                  decoration: const InputDecoration(labelText: 'Select Seat'),
                  items: seats
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedSeat = v),
                ),
                const SizedBox(height: 12),
                // Member selector
                DropdownButtonFormField<ReporteeResponse>(
                  initialValue: selectedReportee,
                  decoration: const InputDecoration(labelText: 'Select Person'),
                  items: availableReportees
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.friendlyName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedReportee = v),
                ),
                const SizedBox(height: 16),
                // Date range display and picker
                Text(
                  'Date Range',
                  style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final range = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: DateTimeRange(
                        start: fromDate,
                        end: toDate,
                      ),
                    );
                    if (range != null) {
                      setDialogState(() {
                        fromDate = range.start;
                        toDate = range.end;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      suffixIcon: const Icon(Icons.calendar_today, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: Text(
                      '${DateFormat('MMM d').format(fromDate)} - ${DateFormat('MMM d, y').format(toDate)}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Day count info
                if (dayCount > 0)
                  Text(
                    '$dayCount day${dayCount != 1 ? 's' : ''} selected',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (dayCount > 90)
                  Text(
                    'Maximum 90 days allowed',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 12),
                // TOTP code
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Enter the 6-digit TOTP code for '),
                      TextSpan(
                        text: selectedReportee?.friendlyName ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' to book.'),
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton.icon(
                          onPressed: () => pasteClipboardCode(codeCtrl, code),
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: Text('Paste code: $code'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => launchAuthenticator(ctx),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open Authenticator App'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!isValid) return;
                if (codeCtrl.text.isEmpty) {
                  showRootSnackBar(
                    const SnackBar(content: Text('Please enter a TOTP code')),
                  );
                  return;
                }
                final fromStr = DateFormat('yyyy-MM-dd').format(fromDate);
                final toStr = DateFormat('yyyy-MM-dd').format(toDate);
                try {
                  final res = await api.bookSeatRange(
                    selectedReportee!.id,
                    selectedSeat!.id,
                    fromStr,
                    toStr,
                    codeCtrl.text,
                  );
                  rangeResult = res;
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    final msg =
                        'Booked ${res.seatLabel}: ${res.confirmedCount} confirmed, '
                        '${res.waitlistedCount} waitlisted, ${res.failedCount} skipped';
                    showRootSnackBar(SnackBar(content: Text(msg)));
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    showRootSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              child: const Text('Book Range'),
            ),
          ],
        );
      },
    ),
  );

  return rangeResult;
}
