import 'package:flutter/material.dart';

/// Reusable TOTP prompt dialog that asks for a 6-digit code.
///
/// Returns the entered code as a [String], or `null` if cancelled.
Future<String?> showTotpPromptDialog(
  BuildContext context, {
  required String title,
  String? entityName,
  String? reason,
  required ValueNotifier<String?> clipboardOtp,
  required void Function(TextEditingController ctrl, String code)
      pasteClipboardCode,
  required void Function(BuildContext ctx) launchAuthenticator,
}) async {
  final codeCtrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (entityName != null && reason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Enter the 6-digit TOTP code for '),
                    TextSpan(
                      text: entityName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ' to ${reason.toLowerCase()}.'),
                  ],
                ),
              ),
            ),
          AutofillGroup(
            child: TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'TOTP Code',
                hintText: '6-digit code',
              ),
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 6,
              autofocus: true,
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: clipboardOtp,
            builder: (context, code, _) {
              if (code == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => pasteClipboardCode(codeCtrl, code),
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: Text('Paste code: $code'),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
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
          onPressed: () => Navigator.pop(ctx, codeCtrl.text),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return result;
}

/// Reusable confirmation dialog with optional destructive styling.
///
/// Returns `true` if confirmed, `false` or `null` if cancelled.
Future<bool?> showConfirmActionDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
