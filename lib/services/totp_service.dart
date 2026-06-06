import 'dart:math';
import 'dart:typed_data';
import 'package:otp/otp.dart';
import 'package:base32/base32.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TotpService {
  static String generateSecret() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(20, (_) => random.nextInt(256)),
    );
    return base32.encode(bytes);
  }

  static String generateCode(String base32Secret) {
    return OTP.generateTOTPCodeString(
      base32Secret,
      DateTime.now().millisecondsSinceEpoch,
      algorithm: Algorithm.SHA1,
      length: 6,
      interval: 30,
      isGoogle: true,
    );
  }

  static bool validate(String base32Secret, String code) {
    final generated = generateCode(base32Secret);
    return generated == code;
  }

  static String getOtpAuthUri(String base32Secret, String label) {
    final encodedLabel = Uri.encodeComponent(label);
    return 'otpauth://totp/$encodedLabel?secret=$base32Secret&issuer=Synapse&algorithm=SHA1&digits=6&period=30';
  }

  // SharedPreferences storage
  static Future<void> storeSecret(
    String entityType,
    int entityId,
    String secret,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('totp_${entityType}_$entityId', secret);
  }

  static Future<String?> getSecret(String entityType, int entityId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('totp_${entityType}_$entityId');
  }

  static Future<void> removeSecret(String entityType, int entityId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('totp_${entityType}_$entityId');
  }
}
