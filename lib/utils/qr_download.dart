import 'dart:ui' as ui;
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/app_colors.dart';

// Web-only imports via conditional
import 'qr_download_stub.dart'
    if (dart.library.html) 'qr_download_web.dart'
    as platform;

Future<String?> downloadQrImage(String data, String filename) async {
  final qrPainter = QrPainter(
    data: data,
    version: QrVersions.auto,
    eyeStyle: QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: AppColors.qrCodeColor,
    ),
    dataModuleStyle: QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: AppColors.qrCodeColor,
    ),
  );

  const size = 300.0;
  const padding = 20.0;
  const totalSize = size + padding * 2;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, totalSize, totalSize),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.translate(padding, padding);
  qrPainter.paint(canvas, const ui.Size(size, size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(totalSize.toInt(), totalSize.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) return null;
  final bytes = byteData.buffer.asUint8List();
  return await platform.saveBytes(bytes, filename);
}
