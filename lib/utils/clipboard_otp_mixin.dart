import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mixin that provides clipboard-based OTP detection and authenticator app
/// launching. Mix into any [State] that also uses [WidgetsBindingObserver].
///
/// Usage:
///   1. Mix in: `with ClipboardOtpMixin`
///   2. Call `initClipboardOtp()` in initState
///   3. Call `disposeClipboardOtp()` in dispose
///   4. Override `didChangeAppLifecycleState` and call
///      `handleLifecycleForOtp(state)` inside it
///   5. Use `clipboardOtp` ValueNotifier in your dialogs
///   6. Call `pasteClipboardCode(controller, code)` from paste buttons
///   7. Call `launchAuthenticator(context)` from authenticator buttons
mixin ClipboardOtpMixin<T extends StatefulWidget> on State<T> {
  final ValueNotifier<String?> clipboardOtp = ValueNotifier(null);
  String? _lastPastedOtp;
  bool awaitingAuthenticatorReturn = false;

  void initClipboardOtp() {
    // no-op for now; reserved for future setup
  }

  void disposeClipboardOtp() {
    clipboardOtp.dispose();
  }

  void handleLifecycleForOtp(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && awaitingAuthenticatorReturn) {
      awaitingAuthenticatorReturn = false;
      checkClipboardForOtp();
    }
  }

  Future<void> checkClipboardForOtp() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final text = data!.text!.trim();
      if (RegExp(r'^\d{6}$').hasMatch(text) && text != _lastPastedOtp) {
        clipboardOtp.value = text;
        return;
      }
    }
    clipboardOtp.value = null;
  }

  void pasteClipboardCode(TextEditingController ctrl, String code) {
    ctrl.text = code;
    _lastPastedOtp = code;
    awaitingAuthenticatorReturn = false;
    clipboardOtp.value = null;
  }

  void resetClipboardOtp() {
    awaitingAuthenticatorReturn = false;
    clipboardOtp.value = null;
  }

  Future<String?> launchAuthenticator(BuildContext ctx) async {
    awaitingAuthenticatorReturn = true;
    final uris = [
      Uri.parse('otpauth://'),
      Uri.parse('googleauthenticator://'),
      Uri.parse('msauth://'),
    ];
    for (final uri in uris) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return null;
        }
      } catch (_) {}
    }
    awaitingAuthenticatorReturn = false;
    return 'No authenticator app found. Please open it manually.';
  }

  Future<String?> launchAuthenticatorWithUri(
    BuildContext ctx,
    String otpUri,
  ) async {
    awaitingAuthenticatorReturn = true;
    final uri = Uri.parse(otpUri);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        awaitingAuthenticatorReturn = false;
        return 'No authenticator app found';
      }
      return null;
    } catch (_) {
      awaitingAuthenticatorReturn = false;
      return 'No authenticator app found';
    }
  }
}
