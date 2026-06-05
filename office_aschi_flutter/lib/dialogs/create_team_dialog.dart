import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/totp_service.dart';
import '../widgets/totp_setup_widget.dart';

/// Dialog for creating a new team. Handles TOTP setup and team creation.
///
/// Returns the created team's ID if successful, or `null` if cancelled.
Future<int?> showCreateTeamDialog(
  BuildContext context, {
  required ValueNotifier<String?> clipboardOtp,
  required void Function(TextEditingController ctrl, String code)
      pasteClipboardCode,
  required void Function(BuildContext ctx, String otpUri)
      launchAuthenticatorWithUri,
}) async {
  final api = ApiService();
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String secret = TotpService.generateSecret();
  String? verifyError;
  String? nameError;
  bool creating = false;
  int? createdTeamId;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final label = nameCtrl.text.isNotEmpty ? nameCtrl.text : 'Team';
        final otpUri = TotpService.getOtpAuthUri(secret, '$label (Manager)');

        return AlertDialog(
          title: const Text('Create Team'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Team Name',
                      errorText: nameError,
                    ),
                    onChanged: (_) {
                      secret = TotpService.generateSecret();
                      codeCtrl.clear();
                      setDialogState(() {
                        verifyError = null;
                        nameError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TotpSetupWidget(
                    otpUri: otpUri,
                    secret: secret,
                    onOpenAuthenticator: () =>
                        launchAuthenticatorWithUri(ctx, otpUri),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Verify TOTP Code',
                      hintText: '6-digit code',
                      errorText: verifyError,
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
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
              onPressed: creating
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        setDialogState(
                          () => nameError = 'Team name is required',
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
                        nameError = null;
                        creating = true;
                      });
                      try {
                        final team = await api.createTeam(
                          nameCtrl.text.trim(),
                          secret,
                          codeCtrl.text,
                        );
                        await TotpService.storeSecret(
                          'manager',
                          team.id,
                          secret,
                        );
                        createdTeamId = team.id;
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setDialogState(() {
                          verifyError = e
                              .toString()
                              .replaceFirst('Exception: ', '');
                          creating = false;
                        });
                      }
                    },
              child: Text(creating ? 'Creating...' : 'Create'),
            ),
          ],
        );
      },
    ),
  );

  return createdTeamId;
}
