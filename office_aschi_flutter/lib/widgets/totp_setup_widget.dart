import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/qr_download.dart';
import '../utils/snackbar_service.dart';

/// Reusable TOTP setup widget displaying:
/// - QR code for authenticator apps
/// - Secret key display
/// - Download QR / Copy Secret / Open Authenticator buttons
///
/// Used in both Create Team and Join Team dialogs.
class TotpSetupWidget extends StatelessWidget {
  final String otpUri;
  final String secret;
  final VoidCallback onOpenAuthenticator;

  const TotpSetupWidget({
    super.key,
    required this.otpUri,
    required this.secret,
    required this.onOpenAuthenticator,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Scan this QR code with your authenticator app',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: otpUri,
            version: QrVersions.auto,
            size: 200,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: cs.primary,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            secret,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                final path = await downloadQrImage(
                  otpUri,
                  'totp-${DateTime.now().millisecondsSinceEpoch}.png',
                );
                if (path != null && context.mounted) {
                  showRootSnackBar(
                    SnackBar(content: Text('QR saved to $path')),
                  );
                }
              },
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download QR'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: secret));
                showRootSnackBar(
                  const SnackBar(content: Text('Secret copied!')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Secret'),
            ),
            ElevatedButton.icon(
              onPressed: onOpenAuthenticator,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open with Authenticator'),
            ),
          ],
        ),
      ],
    );
  }
}
