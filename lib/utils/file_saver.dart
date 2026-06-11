// Platform-agnostic file saver.
// Uses conditional import to pick the right implementation:
// - Native (Android): writes to /storage/emulated/0/Download/
// - Web: triggers browser download via dart:html AnchorElement
import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Save [content] as a file named [fileName].
/// Returns the path or description of where it was saved.
Future<String> saveJsonFile(String fileName, String content) =>
    impl.saveJsonFile(fileName, content);
