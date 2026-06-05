import 'dart:io';
import 'dart:typed_data';

Future<String> saveBytes(Uint8List bytes, String filename) async {
  final dir = Directory('/storage/emulated/0/Download');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  return file.path;
}
