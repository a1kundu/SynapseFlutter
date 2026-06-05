import 'package:flutter/material.dart';

/// Global key for the root [ScaffoldMessenger] whose [Scaffold] sits
/// *above* the [Navigator] in the widget tree.  Snackbars shown through
/// this key are rendered on top of every route overlay, including dialogs.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Show a [SnackBar] at the app-root level, above all routes & dialogs.
void showRootSnackBar(SnackBar snackBar) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
}
