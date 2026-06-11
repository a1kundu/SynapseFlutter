// Native (Android/iOS/desktop) implementation – uses dart:io.
import 'dart:io';

/// Saves [content] to the device Downloads folder and returns the file path.
Future<String> saveJsonFile(String fileName, String content) async {
  final dir = Directory('/storage/emulated/0/Download');
  if (!await dir.exists()) await dir.create(recursive: true);

  final file = File('${dir.path}/$fileName');
  await file.writeAsString(content);
  return 'Downloads/$fileName';
}
