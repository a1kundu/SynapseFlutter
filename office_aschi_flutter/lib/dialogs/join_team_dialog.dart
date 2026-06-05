import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/totp_service.dart';
import '../widgets/totp_setup_widget.dart';

/// Dialog for joining an existing team. Handles name input, TOTP setup,
/// and join request submission.
///
/// Returns the reportee ID if successful, or `null` if cancelled.
Future<int?> showJoinTeamDialog(
  BuildContext context, {
  required int teamId,
  required String? teamName,
  required ValueNotifier<String?> clipboardOtp,
  required void Function(TextEditingController ctrl, String code)
      pasteClipboardCode,
  required void Function(BuildContext ctx, String otpUri)
      launchAuthenticatorWithUri,
}) async {
  final api = ApiService();
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String secret = '';
  String? verifyError;
  bool joining = false;
  int? joinedReporteeId;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final name = nameCtrl.text.trim();
        final hasName = name.isNotEmpty;
        final displayTeamName = teamName ?? 'Team';
        final otpUri = hasName
            ? TotpService.getOtpAuthUri(secret, '$name @ $displayTeamName')
            : '';

        return AlertDialog(
          title: Text('Join ${teamName ?? "Team"}'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Your Name'),
                    onChanged: (_) {
                      final n = nameCtrl.text.trim();
                      if (n.isNotEmpty) {
                        secret = TotpService.generateSecret();
                      } else {
                        secret = '';
                      }
                      codeCtrl.clear();
                      setDialogState(() => verifyError = null);
                    },
                  ),
                  if (hasName) ...[
                    const SizedBox(height: 16),
                    TotpSetupWidget(
                      otpUri: otpUri,
                      secret: secret,
                      onOpenAuthenticator: () =>
                          launchAuthenticatorWithUri(ctx, otpUri),
                    ),
                    const SizedBox(height: 8),
                    AutofillGroup(
                      child: TextField(
                        controller: codeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Verify TOTP Code',
                          hintText: '6-digit code',
                          errorText: verifyError,
                        ),
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
                            onPressed: () {
                              pasteClipboardCode(codeCtrl, code);
                              setDialogState(() {});
                            },
                            icon: const Icon(Icons.content_paste, size: 18),
                            label: Text('Paste code: $code'),
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    Text(
                      'Enter your name to generate a TOTP secret',
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: joining
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(
                          () => verifyError = 'Name is required',
                        );
                        return;
                      }
                      if (codeCtrl.text.length != 6) {
                        setDialogState(
                          () => verifyError = 'Enter 6-digit code',
                        );
                        return;
                      }
                      setDialogState(() {
                        verifyError = null;
                        joining = true;
                      });
                      try {
                        final r = await api.joinTeam(
                          teamId,
                          name,
                          secret,
                          codeCtrl.text,
                        );
                        await TotpService.storeSecret(
                          'reportee',
                          r.id,
                          secret,
                        );
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt('reportee_$teamId', r.id);
                        joinedReporteeId = r.id;
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() {
                          verifyError = e
                              .toString()
                              .replaceFirst('Exception: ', '');
                          joining = false;
                        });
                      }
                    },
              child: Text(joining ? 'Sending Request...' : 'Request to Join'),
            ),
          ],
        );
      },
    ),
  );

  return joinedReporteeId;
}
